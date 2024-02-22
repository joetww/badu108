#!/bin/bash
Folder=`cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`
Agent2Conf="/etc/zabbix/zabbix_agent2.conf"
IN=$(cat ${Agent2Conf} | grep -v '\s*#' | grep -v '^$' | grep -Pho '(Server=.*|ServerActive=.*)$' | sed 's/\(Server=\|ServerActive=\)\(\w\+\)/\2/g')
ServerIP=$(while IFS=',' read -ra ADDR; do 
        for i in "${ADDR[@]}"; do
                RESOLVE="$(dig ${i} +short)"
                test -z "${RESOLVE}" && echo ${i} || echo ${RESOLVE}
        done
done <<< "$IN")

HostName=$(zabbix_agent2 -t agent.hostname | sed 's/.*\[s|\(.*\)\]/\1/g' )

Timestamp=`date +%s`
SendFile=$(mktemp $Folder/TCP_sendAgent2_XXXXX.txt)

ss -tan | tail -n +2 |cut -d" " -f1 > $Folder/TCPAgent2.txt
for i in ESTAB SYN-SENT SYN-RECV FIN-WAIT-1 FIN-WAIT-2 TIME-WAIT CLOSE-WAIT LAST-ACK LISTEN CLOSING ;do
  Result=`fgrep "$i" $Folder/TCPAgent2.txt | wc -l`
  echo "$HostName tcp.status[$i] $Timestamp $Result" >> $SendFile
done

for i in ${ServerIP}; do
       # echo "Server: "
        ZabbixSrv=${i}

        /usr/bin/zabbix_sender -vv --tls-connect cert --tls-ca-file /etc/zabbix/crt/zabbix_root_ca.cert --tls-cert-file /etc/zabbix/crt/zabbix_agent.cert --tls-key-file /etc/zabbix/crt/zabbix_agent.key -z $ZabbixSrv -T -i $SendFile > /dev/null
done
#cat $SendFile
rm -f $SendFile
