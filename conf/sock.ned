-- vim:ft=lua
-- l4re-sock: zwei Linux-Gaeste in eigenen uvmm, verbunden ueber das
-- normale virtio-Netz von L4Re (l4vio_net_p2p, beide Richtungen).
package.path = "rom/?.lua";

local L4  = require "L4";
local vmm = require "vmm";

-- Konsole: cons verteilt die Ausgaben; Strg+E 1 / Strg+E 2 wechselt den Gast
vmm.loader.log_fab = L4.default_loader:new_channel();
L4.default_loader:start(
  {
    scheduler = vmm.new_sched(0x40),
    log = L4.Env.log,
    caps = { cons = vmm.loader.log_fab:svr() },
  }, "rom/cons -a");

-- Netz: ein Kabel mit zwei Enden (l4vio_net_p2p)
local net = { vm1 = 1, vm2 = 1 };
vmm.start_virtio_switch(net, 0xa, nil, "p2p");

for id = 1, 2 do
  vmm.start_vm{
    id       = id,
    mem      = 128,
    net      = net["vm" .. id],
    kernel   = "rom/Image",
    rd       = "rom/sock-rd.cpio.gz",
    fdt      = "rom/virt-arm_virt-64.dtb",
    bootargs = "console=ttyAMA0 earlycon rdinit=/init sock_id=" .. id,
  };
end
