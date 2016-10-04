#!/bin/bash
read -p "Insert connector name:" sn
read -p "Insert version name:" vn
svr="dev" # read -p "Server name: (dev,int,prod)" svr
a="leader.mpp.${svr}.emea.media.global.loc"
dbn="pdw_dev" # read -p "Database name:" dbn
read -p "Password for paraccel: " -s SSHPASS
export SSHPASS

#setting the schemas
pdw="pdw_${sn}_${vn}"
canonical="canonical_${sn}_${sn}_${vn}"

#Dist key check
echo "Checking sort/dist keys and encodings..."
psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "SELECT 
BTRIM(current_database()) AS db_name 
, BTRIM(n.nspname) AS schema_name 
, BTRIM(name) AS tbl_name
,cast(sum(a.attsortkeyord) as bool) 				hassortkey
,cast(sum(cast(a.attisdistkey as INT )) as bool) 	hasdistkey
--,cast(sum(a.attencodingtype) as bool) 				hasencodtype
FROM stv_tbl_perm t 
JOIN pg_class c ON t.id = c.oid::BIGINT 
JOIN pg_attribute a ON c.oid = a.attrelid 
JOIN pg_namespace n ON c.relnamespace = n.oid 
WHERE db_id <> 1 and schema_name in ('${pdw}', '${canonical}')
GROUP BY 1,2,3
HAVING sum(a.attsortkeyord) = 0 OR sum(cast(a.attisdistkey as INT )) = 0" > temp.txt

cat temp.txt

read -r -p "Are you happy with this to continue? [y/N] " response
if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
then
	echo "Good"
else
	echo "Okay. I will exit now..."
	rm temp.txt
	exit 0
fi


rm temp.txt

#Create the analyze compression commands
echo "Creating analyze compression commands..."
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -c "
select 'ANALYZE COMPRESSION '||table_schema||'.'||table_name||';' from information_schema.tables
where table_schema IN ('${canonical}','${pdw}')
and table_name not like '%_history'
and table_type = 'BASE TABLE'" -t > analyzed/analyze_comp.sql

#Run the analyze compression in all tables
echo "Running analyze compression...(This might take a while)"
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -f analyzed/analyze_comp.sql

echo "Moving files..."
#Moving the files locally
sshpass -e scp paraccel@${a}:/tmp/*.ddl /home/mmiche01/MyScripts/analyzed/
#Cleanup the server
sshpass -e ssh paraccel@${a} rm /tmp/*.ddl

echo "Getting table names..."
#Get the table_names
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -c "
select table_schema||'.'||table_name from information_schema.tables
where table_schema IN ('${canonical}','${pdw}')
and table_name not like '%_history'
and table_type = 'BASE TABLE'" -t > analyzed/${sn}.txt

#removes the last empty row
sed '/^\s*$/d' -i analyzed/${sn}.txt
sed -i 's/^[ \t]*//' analyzed/test.txt

echo "Looping through columns..."
#Read all table_names
while IFS='' read -r i || [[ -n "$i" ]]; do
			#echo ${i}
			#Read columns of each table
			psql -h ${a} -p 5439 -U paraccel -w ${dbn} -c "select column_name from information_schema.columns 
			where table_schema IN ('${canonical}','${pdw}') and table_schema||'.'||table_name = '${i}'" -t > analyzed/tmp_columns.txt
			#format
			sed '/^\s*$/d' -i analyzed/tmp_columns.txt
			while IFS='' read -r linec || [[ -n "$linec" ]]; do
				#echo ${linec}
	    		#Reading the DDLs
	    		find /home/mmiche01/MyScripts/analyzed -name "*.${i}*" -exec cat {} \; | awk -v tb="${i}" -v myvar="$linec" '$0 ~ myvar {match($0, /encoding/); print "ALTER TABLE "tb" ALTER COLUMN"myvar" ENCODE " substr($0, RSTART + 9, RLENGTH +10);}' | sed 's/(//'| sed 's/)//'|sed 's/is .*//'|sed 's/vs\. .*//'|sed 's/$/\;/' >> analyzed/tmp_init_alters.sql
	    	done < analyzed/tmp_columns.txt
done < analyzed/test.txt

echo "Reading custom encodings..."
#Reads custom encodings from control db
psql -h postgres.dev.emea.media.global.loc -p 5432 -U mmichelis -w dan_control -c "select * from dan_control.custom_encodings" -t > analyzed/tmp_enc.sql

#formatting
sed '/^\s*$/d' -i analyzed/tmp_enc.sql
sed 's/| //' -i analyzed/tmp_enc.sql
sed 's/ \+/ /g' -i analyzed/tmp_enc.sql
sed 's/^[ \t]*//' -i analyzed/tmp_enc.sql 

#Changing current alter statements with custom encodings
awk 'NR==FNR && a[$1]=$2 {} NR>FNR { k=$6; if (k in a) print $1,$2,$3,$4,$5,k,$7,a[k]";"; else print $0}' analyzed/tmp_enc.sql analyzed/tmp_init_alters.sql > analyzed/alters_${sn}.sql

#padb_export current schemas
echo "Running padb_export on server for pdw schema..."
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc padb_export pdw_dev -n ${pdw} -x -s -O -f ${pdw}.sql
echo "Running padb_export on server for canonical schema..."
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc padb_export pdw_dev -n ${canonical} -x -s -O -f ${canonical}.sql

#Rename old schemas to _old
echo "Renaming current schemata..."
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -c "ALTER SCHEMA ${pdw} RENAME TO ${pdw}_old; ALTER SCHEMA ${canonical} RENAME TO ${canonical}_old;"

#Copy DDLs locally
echo "Copying the file pdw locally..."
sshpass -e scp paraccel@leader.mpp.dev.emea.media.global.loc:/home/paraccel/${pdw}.sql /home/mmiche01/MyScripts/connectors
echo "Copying the file canonical locally..."
sshpass -e scp paraccel@leader.mpp.dev.emea.media.global.loc:/home/paraccel/${canonical}.sql /home/mmiche01/MyScripts/connectors

#Cleanup
echo "Removing generated files from server..."
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc rm ${pdw}.sql
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc rm ${canonical}.sql

#Run DDLs to create new schemas
echo "Creating new schemata..."
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -f connectors/${pdw}.sql
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -f connectors/${canonical}.sql

#Apply encodings 
echo "Applying encodings..."
psql -h ${a} -p 5439 -U paraccel -w ${dbn} -f analyzed/alters_${sn}.sql

#Cleanup tmp files
rm analyzed/*

#drop old schemas
# psql -h ${a} -p 5439 -U paraccel -w ${dbn} -c "DROP SCHEMA ${pdw}_old CASCADE; DROP SCHEMA ${canonical}_old CASCADE;"

exit 0
