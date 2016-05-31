# bash
#!/bin/bash

#parameters
FILE=${1}

read -p "Insert how many databases you want to deploy to:" yn
read -p "Server name: (dev,int,prod)" svr
a="leader.mpp.${svr}.emea.media.global.loc"

for ((i=1; i <= ${yn} ; i++ ))
do
        read -p "Database name:" dbn
        array[$i]=${dbn}
done

for i in ${array[@]}
do
        echo "Running for ${i}..."
        psql -h ${a} -p 5439 -U paraccel ${i} -f ${1} -v ga=${i}_a -v gw=${i}_w -v gr=${i}_r -v go=${i}_o;
done

exit 0

# ############################################################################################ #
