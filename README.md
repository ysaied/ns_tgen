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

### ⚠️ Note for Hypervisor Users (Option 1: Direct-Connected Traffic Generation)

When deploying **Option 1** in virtualized environments, ensure the hypervisor allows the guest VM to assign and transmit custom MAC addresses. This is crucial because the Linux namespaces may use MAC addresses different from those assigned by the hypervisor. To facilitate this:

#### **VMware ESXi**

- Navigate to the settings of the relevant **port group**.
- Under the **Security** tab, set the following policies to **Accept**:
  - **Promiscuous Mode**
  - **MAC Address Changes**
  - **Forged Transmits**

#### **KVM (Kernel-based Virtual Machine)**

- Configure the virtual network interface to allow MAC address changes.
- Ensure that the bridge or virtual network is set to accept traffic from interfaces with custom MAC addresses.
- This may involve setting the interface to **promiscuous mode** or adjusting bridge settings to permit MAC spoofing.

Failing to configure these settings may result in dropped packets or connectivity issues within the simulated network namespaces.

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
chmod +x ns_tgen_direct.sh
sudo ./ns_tgen_direct.sh
sudo ./ns_tgen_direct.sh --delete
# OR
chmod +x ns_tgen_routed.sh
sudo ./ns_tgen_routed.sh
sudo ./ns_tgen_routed.sh --delete
```

---
## 📄 License
This project is licensed under the MIT License. See the LICENSE file for details.

---
## 🤝 Contributing
Contributions are welcome! Please open issues or submit pull requests for enhancements or bug fixes.

---
## 📬 Contact
For questions or support, please open an issue on the GitHub repository.
