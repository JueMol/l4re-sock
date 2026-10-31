/* sockpp: Ping-Pong ueber UDP und TCP zwischen zwei Gaesten
 *
 *   sockpp server [-p PORT]
 *       Echo-Dienst: jedes UDP-Datagramm und alles, was ueber eine
 *       TCP-Verbindung kommt, geht unveraendert zurueck.
 *
 *   sockpp ping HOST [-p PORT] [-n ANZAHL] [-s BYTES]
 *       Schickt ANZAHL Nachrichten per UDP und dann ANZAHL Nachrichten
 *       ueber eine TCP-Verbindung, prueft die Antwort und misst die Zeit
 *       hin und zurueck.
 *
 *   sockpp selftest HOST [-p PORT] [-w SEKUNDEN]
 *       Wartet, bis HOST antwortet (hoechstens -w Sekunden, Standard 300),
 *       macht dann einen kurzen ping und meldet "SELFTEST OK" oder
 *       "SELFTEST FEHLER". Wird beim Start der Gaeste aufgerufen.
 *
 * Standard-Port: 7777 (UDP und TCP).
 */
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAXMSG 65000

static int port = 7777;

static double now_ms(void)
{
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1e3 + t.tv_nsec / 1e6;
}

static int resolve(const char *host, struct sockaddr_in *a)
{
  memset(a, 0, sizeof *a);
  a->sin_family = AF_INET;
  a->sin_port = htons((unsigned short)port);
  if (inet_pton(AF_INET, host, &a->sin_addr) != 1)
    {
      fprintf(stderr, "sockpp: '%s' ist keine IPv4-Adresse\n", host);
      return -1;
    }
  return 0;
}

/* ------------------------------------------------------------------ */
/* Server                                                               */
/* ------------------------------------------------------------------ */

static void tcp_echo(int c)
{
  static char buf[MAXMSG];
  for (;;)
    {
      ssize_t n = read(c, buf, sizeof buf);
      if (n <= 0) break;
      for (ssize_t o = 0; o < n; )
        {
          ssize_t w = write(c, buf + o, (size_t)(n - o));
          if (w <= 0) return;
          o += w;
        }
    }
}

static int server(void)
{
  int u = socket(AF_INET, SOCK_DGRAM, 0);
  int t = socket(AF_INET, SOCK_STREAM, 0);
  if (u < 0 || t < 0) { perror("socket"); return 1; }
  int one = 1;
  setsockopt(t, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

  struct sockaddr_in a = {0};
  a.sin_family = AF_INET;
  a.sin_port = htons((unsigned short)port);
  a.sin_addr.s_addr = INADDR_ANY;
  if (bind(u, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind udp"); return 1; }
  if (bind(t, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind tcp"); return 1; }
  if (listen(t, 8) < 0) { perror("listen"); return 1; }
  signal(SIGCHLD, SIG_IGN);             /* beendete Kinder nicht aufheben */

  fprintf(stderr, "sockpp: Echo-Dienst auf UDP und TCP Port %d\n", port);

  static char buf[MAXMSG];
  struct pollfd p[2] = { { u, POLLIN, 0 }, { t, POLLIN, 0 } };
  for (;;)
    {
      if (poll(p, 2, -1) < 0)
        {
          if (errno == EINTR) continue;
          perror("poll");
          return 1;
        }
      if (p[0].revents & POLLIN)
        {
          struct sockaddr_in from;
          socklen_t fl = sizeof from;
          ssize_t n = recvfrom(u, buf, sizeof buf, 0, (struct sockaddr *)&from, &fl);
          if (n >= 0)
            sendto(u, buf, (size_t)n, 0, (struct sockaddr *)&from, fl);
        }
      if (p[1].revents & POLLIN)
        {
          int c = accept(t, NULL, NULL);
          if (c < 0) continue;
          pid_t pid = fork();
          if (pid == 0)
            {
              close(u);
              close(t);
              tcp_echo(c);
              _exit(0);
            }
          close(c);
        }
    }
}

/* ------------------------------------------------------------------ */
/* Ping                                                                 */
/* ------------------------------------------------------------------ */

static void fill(char *m, int size, int nr)
{
  for (int i = 0; i < size; ++i)
    m[i] = (char)('a' + (nr + i) % 26);
}

/* UDP: n Nachrichten, je bis zu timeout_ms warten. Gibt die Zahl der
 * richtigen Antworten zurueck. */
static int ping_udp(const struct sockaddr_in *a, int n, int size, int timeout_ms, int quiet)
{
  int s = socket(AF_INET, SOCK_DGRAM, 0);
  if (s < 0) { perror("socket"); return 0; }
  if (connect(s, (const struct sockaddr *)a, sizeof *a) < 0) { perror("connect"); close(s); return 0; }

  static char out[MAXMSG], in[MAXMSG];
  int ok = 0;
  for (int i = 1; i <= n; ++i)
    {
      fill(out, size, i);
      double t0 = now_ms();
      if (send(s, out, (size_t)size, 0) < 0)
        {
          if (!quiet) printf("UDP  #%-3d Fehler beim Senden: %s\n", i, strerror(errno));
          continue;
        }
      struct pollfd p = { s, POLLIN, 0 };
      int got = 0;
      while (!got)
        {
          int left = timeout_ms - (int)(now_ms() - t0);
          if (left <= 0 || poll(&p, 1, left) <= 0) break;
          ssize_t r = recv(s, in, sizeof in, 0);
          if (r < 0) break;                           /* z. B. ECONNREFUSED */
          if (r == size && !memcmp(in, out, (size_t)size)) got = 1;
          /* sonst: verspaetete Antwort auf eine fruehere Nachricht, weiter warten */
        }
      double dt = now_ms() - t0;
      if (got)
        {
          ok++;
          if (!quiet) printf("UDP  #%-3d %5d Bytes  %8.3f ms\n", i, size, dt);
        }
      else if (!quiet)
        printf("UDP  #%-3d keine Antwort\n", i);
      fflush(stdout);
    }
  close(s);
  return ok;
}

static int read_full(int s, char *b, int len, int timeout_ms, double t0)
{
  int got = 0;
  struct pollfd p = { s, POLLIN, 0 };
  while (got < len)
    {
      int left = timeout_ms - (int)(now_ms() - t0);
      if (left <= 0 || poll(&p, 1, left) <= 0) return -1;
      ssize_t r = read(s, b + got, (size_t)(len - got));
      if (r <= 0) return -1;
      got += (int)r;
    }
  return 0;
}

/* TCP: eine Verbindung, n Nachrichten hin und zurueck. */
static int ping_tcp(const struct sockaddr_in *a, int n, int size, int timeout_ms)
{
  int s = socket(AF_INET, SOCK_STREAM, 0);
  if (s < 0) { perror("socket"); return 0; }
  int one = 1;
  setsockopt(s, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);

  double t0 = now_ms();
  if (connect(s, (const struct sockaddr *)a, sizeof *a) < 0)
    {
      printf("TCP  Verbindung fehlgeschlagen: %s\n", strerror(errno));
      close(s);
      return 0;
    }
  printf("TCP  verbunden            %8.3f ms\n", now_ms() - t0);

  static char out[MAXMSG], in[MAXMSG];
  int ok = 0;
  for (int i = 1; i <= n; ++i)
    {
      fill(out, size, i);
      t0 = now_ms();
      ssize_t w = 0;
      for (int o = 0; o < size; o += (int)w)
        if ((w = write(s, out + o, (size_t)(size - o))) <= 0) break;
      if (w <= 0 || read_full(s, in, size, timeout_ms, t0) < 0)
        {
          printf("TCP  #%-3d keine Antwort\n", i);
          break;
        }
      double dt = now_ms() - t0;
      if (memcmp(in, out, (size_t)size))
        printf("TCP  #%-3d Antwort falsch\n", i);
      else
        {
          ok++;
          printf("TCP  #%-3d %5d Bytes  %8.3f ms\n", i, size, dt);
        }
      fflush(stdout);
    }
  close(s);
  return ok;
}

static int ping(const char *host, int n, int size)
{
  struct sockaddr_in a;
  if (resolve(host, &a) < 0) return 2;
  printf("Ping-Pong mit %s Port %d: %d x UDP, %d x TCP, je %d Bytes\n",
         host, port, n, n, size);
  int u = ping_udp(&a, n, size, 2000, 0);
  int t = ping_tcp(&a, n, size, 5000);
  printf("Ergebnis: UDP %d/%d, TCP %d/%d %s\n", u, n, t, n,
         (u == n && t == n) ? "ok" : "FEHLER");
  return (u == n && t == n) ? 0 : 1;
}

static int selftest(const char *host, int wait_s)
{
  struct sockaddr_in a;
  if (resolve(host, &a) < 0) return 2;
  printf("Selbsttest: warte auf %s (hoechstens %d s) ...\n", host, wait_s);
  fflush(stdout);
  double t0 = now_ms();
  while (ping_udp(&a, 1, 32, 1000, 1) != 1)
    {
      if (now_ms() - t0 > wait_s * 1000.0)
        {
          printf("SELFTEST FEHLER: %s antwortet nicht\n", host);
          return 1;
        }
      sleep(1);
    }
  printf("%s antwortet nach %.1f s\n", host, (now_ms() - t0) / 1000);
  int r = ping(host, 3, 64);
  printf(r == 0 ? "SELFTEST OK\n" : "SELFTEST FEHLER\n");
  return r;
}

/* ------------------------------------------------------------------ */

static void usage(void)
{
  fprintf(stderr,
          "Aufruf: sockpp server [-p PORT]\n"
          "        sockpp ping HOST [-p PORT] [-n ANZAHL] [-s BYTES]\n"
          "        sockpp selftest HOST [-p PORT] [-w SEKUNDEN]\n");
  exit(2);
}

int main(int argc, char **argv)
{
  if (argc < 2) usage();
  const char *cmd = argv[1];
  int n = 5, size = 64, wait_s = 300, opt;
  optind = 2;
  while ((opt = getopt(argc, argv, "p:n:s:w:")) != -1)
    switch (opt)
      {
      case 'p': port = atoi(optarg); break;
      case 'n': n = atoi(optarg); break;
      case 's': size = atoi(optarg); break;
      case 'w': wait_s = atoi(optarg); break;
      default: usage();
      }
  if (n < 1) n = 1;
  if (size < 1) size = 1;
  if (size > MAXMSG) size = MAXMSG;

  if (!strcmp(cmd, "server"))
    return server();
  if (!strcmp(cmd, "ping") && optind == argc - 1)
    return ping(argv[optind], n, size);
  if (!strcmp(cmd, "selftest") && optind == argc - 1)
    return selftest(argv[optind], wait_s);
  usage();
  return 2;
}
