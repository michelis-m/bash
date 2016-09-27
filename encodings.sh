#!/bin/bash
read -p "Insert connector name:" sn
read -p "Insert version name:" vn
read -p "Server name: (dev,int,prod)" svr
a="leader.mpp.${svr}.emea.media.global.loc"
read -p "Database name:" dbn
read -p "Password for paraccel: " -s SSHPASS
export SSHPASS

pdw="pdw_${sn}_${vn}"
canonical="canonical_${sn}_${sn}_${vn}"

#Create the analyze compression commands
echo "Creating analyze compression commands..."
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -c "
select 'ANALYZE COMPRESSION '||table_schema||'.'||table_name||';' from information_schema.tables
where table_schema IN ('${canonical}','${pdw}')
and table_name not like '%_history'
and table_type = 'BASE TABLE'" -t > analyze_comp.sql

#Run the analyze compression in all tables
echo "Running analyze compression...(This might take a while)"
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -f analyze_comp.sql

#Moving the files locally
sshpass -e scp paraccel@${a}:/tmp/*.ddl /home/mmiche01/MyScripts/analyzed/
#Cleanup
sshpass -e ssh paraccel@${a} rm /tmp/*.ddl

#Get the table_names
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -c "
select table_name from information_schema.tables
where table_schema IN ('${canonical}','${pdw}')
and table_name not like '%_history'
and table_type = 'BASE TABLE'" -t > analyzed/${sn}.txt

sed '/^\s*$/d' -i analyzed/${sn}.txt

i=0
j=0

rm tmp1.sql

for i in ${array[@]}
do
	echo $i
	psql -h ${a} -p 5439 -U paraccel -w ${dbn} -c "select column_name from information_schema.columns
	where table_schema IN ('${canonical}','${pdw}') and table_name = '${i}'" -t > tmp.txt
	
	sed '/^\s*$/d' -i tmp.txt


	#Read each column
	while IFS='' read -r linec || [[ -n "$linec" ]]; do
    	#echo "Column: $linec"
    	#Storing column_names in an array
    	array1[$j]=${linec}

    	#Reading the DDLs
    	find /home/mmiche01/MyScripts/analyzed -name "*.${i}*" -exec cat {} \; | awk -v tb="${i}" -v myvar="$linec" '$0 ~ myvar {match($0, /encoding/); print "ALTER TABLE "tb" ALTER COLUMN"myvar" ENCODE " substr($0, RSTART + 9, RLENGTH +10);}' | sed 's/(//'| sed 's/)//'|sed 's/is .*//'|sed 's/vs\. .*//'|sed 's/$/\;/' >> tmp1.sql


    	j=$((i+1))

	done < tmp.txt

done

#to be changed. Will read the encoding custom formats
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -c "select * from dontdelete" -t > tmp_enc.sql
#formatting
sed '/^\s*$/d' -i tmp_enc.sql
sed 's/| //' -i tmp_enc.sql
sed 's/ \+/ /g' -i tmp_enc.sql
sed 's/^[ \t]*//' -i tmp_enc.sql 

awk 'NR==FNR && a[$1]=$2 {} NR>FNR { k=$6; if (k in a) print $1,$2,$3,$4,$5,k,$7,a[k]";"; else print $0}' tmp_enc.sql tmp1.sql > alters_${sn}.sql

#padb_export current schemas
echo "Running padb_export on server for pdw schema..."
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc padb_export pdw_dev -n ${pdw} -x -s -O -f ${pdw}.sql
echo "Running padb_export on server for canonical schema..."
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc padb_export pdw_dev -n ${canonical} -x -s -O -f ${canonical}.sql


exit 0
