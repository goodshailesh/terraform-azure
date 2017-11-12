#Variables
#============================
variable subscription_id 		 	{}
variable client_id 			 	{}
variable client_secret 			 	{}
variable tenant_id 			 	{}
variable location 			 	{}
variable resource_group 		 	{}
variable count				 	{}
variable environment 			 	{}
variable nsg 				 	{}
variable allowed_cidr_ssh		 	{}
variable virtual_network 		 	{}
variable virtual_network_cidr 		 	{}
variable vmsize 			 	{}
variable publisher 			 	{}
variable offer 				 	{}
variable sku 				 	{}
variable username			 	{}
variable public_key_path		 	{}
variable assurity_splash_local_file_path 	{}
variable assurity_header_local_file_path 	{}
variable provisioner_script_local_file_path	{}
variable vm_extension_publisher			{}
variable vm_extension_type			{}
variable vm_type_handler_version		{}

#Required Version, Remote state conifguration with implicit lock
#===============================
terraform {
	required_version	= ">= 0.10.8"
	backend "azurerm" {
		storage_account_name 	= "remotestateterraform"
		container_name      	= "terraform-remote-state"
		key			= "azure.terraform.tfstate"
		access_key		= "GXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXg=="
	}
}


#Provider
#============================

provider "azurerm" {
	subscription_id = "${var.subscription_id}"
	client_id       = "${var.client_id}"
	client_secret   = "${var.client_secret}"
	tenant_id       = "${var.tenant_id}"
}

#Resources
#===========================
resource "azurerm_resource_group" "rg" {
	name		= "${var.resource_group}"
	location	= "${var.location}"
	tags {
		environment	= "${var.environment}"
	}
}


resource "azurerm_network_security_group" "nsg"{
	name			= "${var.nsg}"
	location		= "${var.location}"
	resource_group_name	= "${azurerm_resource_group.rg.name}"
	tags {
		environment	= "${var.environment}"
	}
}

resource "azurerm_network_security_rule" "nsgrule" {
	depends_on		    = ["azurerm_network_security_group.nsg"]
	name                        = "allow_ssh"
	priority                    = "100"
	direction                   = "Inbound"
	access                      = "Allow"
	protocol                    = "Tcp"
	source_port_range           = "*"
	destination_port_range      = "22"
	source_address_prefix       = "${coalesce(var.allowed_cidr_ssh, "0.0.0.0/0")}"
	destination_address_prefix  = "*"
	resource_group_name         = "${azurerm_resource_group.rg.name}"
	network_security_group_name = "${azurerm_network_security_group.nsg.name}"
}

resource "azurerm_public_ip" "public-ip" {
	count			     = "${var.count}"
	name                         = "${format("PUB-IP-%d", count.index + 1)}"
	location                     = "${var.location}"
	resource_group_name          = "${azurerm_resource_group.rg.name}"
	public_ip_address_allocation = "Dynamic"
	domain_name_label	     = "${format("vm-%d", count.index + 1)}"

	tags {
		environment = "${var.environment}"
	}
}

resource "azurerm_virtual_network" "vnet" {
	name                = "${var.virtual_network}"
	resource_group_name = "${azurerm_resource_group.rg.name}"
	address_space       = ["${var.virtual_network_cidr}"]
	location            = "${var.location}"
	tags {
		environment = "${var.environment}"
	}
}

resource "azurerm_subnet" "subnets" {
	count		     = "${var.count}"
	name                 = "${format("SNET-%d", count.index + 1)}"
	resource_group_name  = "${azurerm_resource_group.rg.name}"
	virtual_network_name = "${azurerm_virtual_network.vnet.name}"
	address_prefix       = "${cidrsubnet(var.virtual_network_cidr, 8, count.index + 1)}"
}


resource "azurerm_network_interface" "nics" {
	count		    		= "${var.count}"
	name                		= "${format("NIC-%d", count.index + 1)}"
	location            		= "${var.location}"
	resource_group_name 		= "${azurerm_resource_group.rg.name}"
	network_security_group_id	= "${azurerm_network_security_group.nsg.id}"

	ip_configuration {
		name                          = "${format("NIC-IPCONF-%d", count.index + 1)}"
		subnet_id                     = "${element(azurerm_subnet.subnets.*.id, count.index)}"
		private_ip_address_allocation = "Dynamic"
		public_ip_address_id	      = "${element(azurerm_public_ip.public-ip.*.id, count.index)}"
	}
	tags {
		environment = "${var.environment}"
	}
}

resource "azurerm_storage_account" "sa" {
	name                     = "shaileshsa"
	resource_group_name      = "${azurerm_resource_group.rg.name}"
	location                 = "${var.location}"
	account_tier		 = "Standard"
	account_replication_type = "LRS"
	account_kind	 	 = "Storage"
	tags{
		environment	= "${var.environment}"
	}
}

resource "azurerm_storage_container" "cont" {
	name                  = "vhds"
	resource_group_name   = "${azurerm_resource_group.rg.name}"
	storage_account_name  = "${azurerm_storage_account.sa.name}"
	container_access_type = "private"
}

#Blob Container for uploading local file to into it, so that "Custom Script Extension with Linux" can use it

resource "azurerm_storage_container" "provisioning-data" {
	name			= "files"
	resource_group_name	= "${azurerm_resource_group.rg.name}"
	storage_account_name	= "${azurerm_storage_account.sa.name}"
	container_access_type	= "blob"
}

#Uploading provisioning data files to the container
resource "azurerm_storage_blob" "assurity-splash" {
	name			= "assurity.splash"
	resource_group_name	= "${azurerm_resource_group.rg.name}"
	storage_account_name	= "${azurerm_storage_account.sa.name}"
	storage_container_name	= "${azurerm_storage_container.provisioning-data.name}"
	source			= "${var.assurity_splash_local_file_path}"
	type			= "block"
}

resource "azurerm_storage_blob" "assurity-header" {
	name			= "00-header"
	resource_group_name	= "${azurerm_resource_group.rg.name}"
	storage_account_name	= "${azurerm_storage_account.sa.name}"
	storage_container_name	= "${azurerm_storage_container.provisioning-data.name}"
	source			= "${var.assurity_header_local_file_path}"
	type			= "block"
}
resource "azurerm_storage_blob" "provisioner-script" {
	name			= "provisioner.sh"
	resource_group_name	= "${azurerm_resource_group.rg.name}"
	storage_account_name	= "${azurerm_storage_account.sa.name}"
	storage_container_name	= "${azurerm_storage_container.provisioning-data.name}"
	source			= "${var.provisioner_script_local_file_path}"
	type			= "block"
}

resource "azurerm_virtual_machine" "vms" {
	count		      = "${var.count}"
	name                  = "${format("VM-%d", count.index + 1)}"
	location              = "${var.location}"
	resource_group_name   = "${azurerm_resource_group.rg.name}"
	network_interface_ids = ["${element(azurerm_network_interface.nics.*.id, count.index)}"]
	vm_size               = "${var.vmsize}"

# Uncomment this line to delete the OS disk automatically when deleting the VM
	delete_os_disk_on_termination = true

# Uncomment this line to delete the data disks automatically when deleting the VM
	delete_data_disks_on_termination = true

	storage_image_reference {
		publisher = "${var.publisher}"
		offer     = "${var.offer}"
		sku       = "${var.sku}"
		version   = "latest"
	}

	storage_os_disk {
		name          = "${format("osdisk-vm-%d", count.index + 1)}"
		vhd_uri       = "${format("%s%s/%s.vhd",azurerm_storage_account.sa.primary_blob_endpoint, azurerm_storage_container.cont.name, format("osdisk-vm-%d", count.index + 1))}"
		caching       = "ReadWrite"
		create_option = "FromImage"
	}

# Optional data disks
	storage_data_disk {
		name          = "${format("datadisk-vm-%d", count.index + 1)}"
		vhd_uri       = "${format("%s%s/%s.vhd", azurerm_storage_account.sa.primary_blob_endpoint, azurerm_storage_container.cont.name, format("datadisk-vm-%d", count.index  + 1))}"
		disk_size_gb  = "1023"
		create_option = "Empty"
		lun           = 0
	}

	os_profile {
		computer_name  = "${format("vm-%d", count.index + 1)}"
		admin_username = "${var.username}"
	}

	os_profile_linux_config {
		disable_password_authentication = true
		ssh_keys       = [{
			path	= "${format("/home/%s/.ssh/authorized_keys", var.username)}"
			key_data= "${file(var.public_key_path)}"
		}]
	}
	tags {
		environment = "${var.environment}"
	}
}
resource "azurerm_virtual_machine_extension" "vm-linux-extension" {
	count				= "${var.count}"
	name				= "${format("motd-setup-%d", count.index + 1)}"
	location			= "${var.location}"
	resource_group_name		= "${azurerm_resource_group.rg.name}"
	virtual_machine_name		= "${element(azurerm_virtual_machine.vms.*.name, count.index)}"
	publisher			= "${var.vm_extension_publisher}"
	type				= "${var.vm_extension_type}"
	type_handler_version		= "${var.vm_type_handler_version}"
	auto_upgrade_minor_version	= true
	settings = <<EXTENTION
	{
		"fileUris": [
				"${azurerm_storage_blob.provisioner-script.url}"
		],
		"commandToExecute": "${format("sh provisioner.sh %s %s", azurerm_storage_blob.assurity-header.url, azurerm_storage_blob.assurity-splash.url)}"
	}
	EXTENTION
}


output "domain_name_fqdn" {
	value		= "${azurerm_public_ip.public-ip.*.fqdn}"
}
output "login-username" {
	value		= "${var.username}"
}
