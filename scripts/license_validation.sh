#!/bin/bash

wget https://raw.githubusercontent.com/Ganesh-Yeole/quickstart-aks-boomi-molecule/main/scripts/requirements.txt
wget https://raw.githubusercontent.com/Ganesh-Yeole/quickstart-aks-boomi-molecule/main/scripts/license_validation.py

pip install -t . -r ./requirements.txt

if [ $BOOMIAUTHENTICATIONTYPE == "token" ]
then
    result=`python license_validation.py "$MOLECULEACCOUNTID" "BOOMI_TOKEN.$MOLECULEUSERNAME" "$BOOMIMFAAPITOKEN" MOLECULE 60`
else
    result=`python license_validation.py "$MOLECULEACCOUNTID" "$MOLECULEUSERNAME" "$MOLECULEPASSWORD" MOLECULE 60`
fi

status=`echo $result|cut -d, -f1|awk -F':' '{ print $2 }'`
token=`echo $result|cut -d, -f2|awk -F':' '{ print $2 }'`

echo \{\"license_validation\":\"$status\"\, \"installation_token\":\"$token\"\} > $AZ_SCRIPTS_OUTPUT_PATH
