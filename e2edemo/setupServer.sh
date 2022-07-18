#!/bin/bash
main(){
    eval $(parse_yaml initParams.yml)

    # echo $azure_iothub

    createNewDevice="This is a new device "
    useExistedDevice="This is an existed device in Azure IoT service "

    echo -e "\n\n----------------IoT Edge Setup detail---------------\n"
    echo "Azure Subscription": $azure_SubscriptionID
    echo "Resource Group": $azure_ResourceGroup
    echo "DPS name:" $azure_DPSName
    echo "DPS scope:" $azure_DPSScope
    echo "Device Name:" $device_name
    echo -e "\n----------------------------------------------------\n\nChoose an option"


    select yn in "$createNewDevice" "$useExistedDevice" "Exit"; do
        case $yn in
            "$createNewDevice" ) boolCreateDevice=1;break;;
            "$useExistedDevice" ) boolCreateDevice=0;break;;
            "Exit" ) exit;;
        esac
    done 
    DPSConfig $azure_SubscriptionID  $azure_ResourceGroup $azure_DPSName $device_name $boolCreateDevice;
    installIoTEdge $azure_DPSScope $device_name;
}

#arguments: subscriptionID, resourceGroup, DPS name, Device ID, bool_createDevice(1 or 0)
deviceKey="unknown"
DPSConfig(){ 
    echo "---set up azure cli environment..."
    az account set --subscription $1
    az configure --defaults group=$2
    az extension add --name azure-iot
    
    if [ $5 == 1 ]; then
        echo "---Register device in DPS"
        az iot dps enrollment create -g $2 --edge-enabled true --dps-name $3 --enrollment-id $4 --attestation-type symmetrickey &>/dev/null
    fi
    deviceKey=$(az iot dps enrollment show --dps-name $3 --enrollment-id $4  --show-keys --query "attestation.symmetricKey.primaryKey" | tr -d '"')
    #because devicekey will be used as regular expression in sed, so replace possible / as \/
    deviceKey=$(echo $deviceKey | sed 's/\//\\\//g')  
    # echo $deviceKey
}


#arguments: DPS scopeID, Device ID
installIoTEdge(){
    echo -e "---Install IoT Edge runtime, please choose OS option"

    select yn in "ubuntu20" "ubuntu18" "Exit"; do
        case $yn in
            "ubuntu20" ) ubuntu=20;break;;
            "ubuntu18" ) ubuntu=18;break;;
            "Exit" ) exit;;
        esac
    done

    echo -e "---Preparation"
    if [ $ubuntu == 20 ]; then
        wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    elif [ $ubuntu == 18 ]; then
        wget https://packages.microsoft.com/config/ubuntu/18.04/multiarch/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    fi
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
    
    echo -e "---Install Moby container engine"
    sudo apt-get update
    sudo apt-get -y install moby-engine
    sudo touch /etc/docker/daemon.json
    sudo chown $USER /etc/docker/daemon.json
    echo -e '{\n   "log-driver": "local"\n}' > /etc/docker/daemon.json
    echo -e "---Restart container engine to apply change"
    sudo systemctl restart docker

    echo "---Install IoT Edge runtime"
    sudo apt-get -y install aziot-edge defender-iot-micro-agent-edge
    echo "---Modify IoT Edge configuration to include device provisioning information"
    sudo cp templateConfig.toml /etc/aziot/config.toml
    sudo sed -i -e "s/{DPSSCOPE}/$1/g;s/{DEVICEID}/$2/g;s/{SECRETKEY}/$deviceKey/g" /etc/aziot/config.toml
    sudo iotedge config apply -c '/etc/aziot/config.toml'
}



parse_yaml() {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

main "$@"; exit