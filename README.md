# ns-tgen: Linux Namespace Traffic Generator

`ns-tgen` is a simple yet powerful traffic generator based on Linux network namespaces.  
It is designed for testing firewalls, routers, and network appliances with **two flexible deployment options**.

---

## 🌟 Features

✅ Fully containerless traffic generation using Linux namespaces and veth pairs  
✅ Stateless and stateful HTTP traffic simulation (via `curl` and `lighttpd`)  
✅ Two routing models to test different firewall scenarios  
✅ Clean, verbose shell scripts — easy to understand and customize  
✅ Automatically installs required packages (e.g., `lighttpd`) if missing  
✅ Safe cleanup (`--delete` option) to remove all resources

---

## 🔧 Options

### 🟢 Option 1: **Direct-Connected Traffic Generation**  
**Script file:** `ns_tgen_direct.sh`  
- Each namespace (client and server) is directly connected to the DUT (firewall).  
- DUT acts as the default gateway for all namespaces.  
- Simple Layer 2 (bridged) testing.
![Direct-Connected Traffic Generation](https://github.com/user-attachments/assets/6732ca9d-1c3f-49b7-97b9-bc537ecacc11)

### 🟠 Option 2: **Routed Traffic Generation (One-hop away)**  
**Script file:** `ns_tgen_routed.sh`  
- Namespaces are in private subnets (`192.168.1.x` and `192.168.2.x`).  
- Only the Linux VM’s physical interfaces (`eth1`, `eth2`) face the DUT directly.  
- Traffic from namespaces is routed via the Linux VM to the DUT.  
- Closer to real-world deployment scenarios.
![Routed Traffic Generation](https://github.com/user-attachments/assets/11286251-a9fc-4ed8-ad52-766d58d7769b)

---

## 🏗️ Usage

✅ **To create/dete the lab:**
```bash
sudo ./ns_tgen_direct.sh
sudo ./ns_tgen_direct.sh --delete
# OR
sudo ./ns_tgen_routed.sh
sudo ./ns_tgen_routed.sh --delete


