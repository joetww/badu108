#!/bin/bash
Folder=`cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd`
Agent2Conf="/etc/zabbix/zabbix_agent2.conf"
IN=$(cat ${Agent2Conf} | grep -v '\s*#' | grep -v '^$' | grep -Pho '(Server=.*|ServerActive=.*)$' | sed 's/\(Server=\|ServerActive=\)\(\w\+\)/\2/g')
ServerIP=$(while IFS=',' read -ra ADDR; do 
        for i in "${ADDR[@]}"; do
                RESOLVE="$(dig ${i} +short)"
                test -z "${RESOLVE}" && echo ${i}
        done
done <<< "$IN")
AddrList=$Folder/Web_PS.txt
HostName=$(zabbix_agent2 -t agent.hostname | sed 's/.*\[s|\(.*\)\]/\1/g' )

CURLTEST () {
        Result_HttpCode=`curl -I -m 8 -o /dev/null -s -w %{http_code}"\n" -X POST "http://$1"`
        Result_CurlTimeTotal=`curl -I -m 8 -o /dev/null -s -w %{time_total}"\n" -X POST "http://$1"`
        CurlTime=`echo "$Result_CurlTimeTotal"`
        if [ "$Result_HttpCode" == "200" ] ;then
                echo "$HostName apicurl.time[$1] $Timestamp 0"  >> $SendFile
        elif [ "$Result_HttpCode" == "404" ] ;then
                echo "$HostName apicurl.time[$1] $Timestamp 4" >> $SendFile
        else
                echo "$HostName apicurl.time[$1] $Timestamp 10" >> $SendFile
        fi
}

#ZabbixSrv=`cat /etc/zabbix/zabbix_agentd.conf |sed -n "s/^ *Server=\([0-9.]\+\)$/\1/p" |tail -n1`
#ZabbixSrv=`dig "zbx-pfedge.bananatomcat.com" +short`
Timestamp=`date +%s`
SendFile=$(mktemp $Folder/chkServerHttpCodeAgent2_XXXXX.txt)



for i in ${ServerIP}; do
       # echo "Server: "
        ZabbixSrv=${i}

        x=0
        while read -r ADDR ;do
                if [ ! -z "$ADDR" ] ;then
                CURLTEST $ADDR &
                pids[${x}]=$!
                let "x++"
        fi
        done < "$AddrList"
	for pid in ${pids[*]}; do
		wait $pid
	done
        /usr/bin/zabbix_sender -vv --tls-connect cert \
                --tls-ca-file /etc/zabbix/crt/zabbix_root_ca.cert \
                --tls-cert-file /etc/zabbix/crt/zabbix_agent.cert \
                --tls-key-file /etc/zabbix/crt/zabbix_agent.key -z $ZabbixSrv -T -i $SendFile > /dev/null
	#cat $SendFile
        rm -f $SendFile
done

