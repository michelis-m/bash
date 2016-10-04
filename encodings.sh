#!/bin/bash
read -p "Insert connector name:" sn
read -p "Insert version name:" vn
read -p "Password for paraccel: " -s SSHPASS
export SSHPASS

pdw="pdw_${sn}_${vn}"
canonical="canonical_${sn}_${sn}_${vn}"

echo "Checking sort/dist keys and encodings..."
psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "SELECT 
BTRIM(current_database()) AS db_name 
, BTRIM(n.nspname) AS schema_name 
, BTRIM(name) AS tbl_name
,cast(sum(a.attsortkeyord) as bool) 				hassortkey
,cast(sum(cast(a.attisdistkey as INT )) as bool) 	hasdistkey
,cast(sum(a.attencodingtype) as bool) 				hasencodtype
FROM stv_tbl_perm t 
JOIN pg_class c ON t.id = c.oid::BIGINT 
JOIN pg_attribute a ON c.oid = a.attrelid 
JOIN pg_namespace n ON c.relnamespace = n.oid 
WHERE db_id <> 1 and schema_name in ('${pdw}', '${canonical}')
GROUP BY 1,2,3
HAVING sum(a.attsortkeyord) = 0 OR sum(cast(a.attisdistkey as INT )) = 0 
OR sum(a.attencodingtype) = 0" > temp.txt

cat temp.txt

read -r -p "Are you happy with this? [y/N] " response
if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
then
	echo "Good"
else
	echo "Not good. I will exit now..."
	rm temp.txt
	exit 0
fi


rm temp.txt

echo "Running padb_export on server for pdw schema..."
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc padb_export pdw_dev -n ${pdw} -x -s -O -f ${pdw}.sql
echo "Running padb_export on server for canonical schema..."
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc padb_export pdw_dev -n ${canonical} -x -s -O -f ${canonical}.sql

echo "Copying the file pdw locally..."
sshpass -e scp paraccel@leader.mpp.dev.emea.media.global.loc:/home/paraccel/${pdw}.sql /home/mmiche01/MyScripts
echo "Copying the file canonical locally..."
sshpass -e scp paraccel@leader.mpp.dev.emea.media.global.loc:/home/paraccel/${canonical}.sql /home/mmiche01/MyScripts

echo "Removing generated files from server..."
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc rm ${pdw}.sql
sshpass -e ssh paraccel@leader.mpp.dev.emea.media.global.loc rm ${canonical}.sql

echo "Generating ACLs..."
#_a group
psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "select 'ALTER TABLE '||table_schema||'.'||table_name||' OWNER TO :ga ;' from information_schema.tables
where table_schema IN ('${canonical}', '${pdw}');" -t > ${sn}_ACLs.sql

psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "select 'GRANT ALL ON '||table_schema||'.'||table_name||' TO GROUP :ga ;' from information_schema.tables
where table_schema IN ('${canonical}', '${pdw}');" -t >> ${sn}_ACLs.sql

#_w group
psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "select 'GRANT SELECT ON '||table_schema||'.'||table_name||' TO GROUP :gw ;' from information_schema.tables
where table_schema IN ('${canonical}', '${pdw}');" -t >> ${sn}_ACLs.sql

psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "select 'GRANT INSERT ON '||table_schema||'.'||table_name||' TO GROUP :gw ;' from information_schema.tables
where table_schema IN ('${canonical}', '${pdw}');" -t >> ${sn}_ACLs.sql

psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "select 'GRANT UPDATE ON '||table_schema||'.'||table_name||' TO GROUP :gw ;' from information_schema.tables
where table_schema IN ('${canonical}', '${pdw}');" -t >> ${sn}_ACLs.sql

psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "select 'GRANT DELETE ON '||table_schema||'.'||table_name||' TO GROUP :gw ;' from information_schema.tables
where table_schema IN ('${canonical}', '${pdw}');" -t >> ${sn}_ACLs.sql

#_r group
psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "select 'GRANT SELECT ON '||table_schema||'.'||table_name||' TO GROUP :gr ;' from information_schema.tables
where table_schema IN ('${canonical}', '${pdw}');" -t >> ${sn}_ACLs.sql

#_o group
psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "select 'GRANT SELECT ON '||table_schema||'.'||table_name||' TO GROUP :go ;' from information_schema.tables
where table_schema IN ('${canonical}', '${pdw}');" -t >> ${sn}_ACLs.sql

psql -h leader.mpp.dev.emea.media.global.loc -p 5439 -U paraccel -w pdw_dev -c "select 'GRANT REFERENCES ON '||table_schema||'.'||table_name||' TO GROUP :go ;' from information_schema.tables
where table_schema IN ('${canonical}', '${pdw}');" -t >> ${sn}_ACLs.sql

############################################# Deployment to INT ############################################
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
	echo "Running for ${i} pdw schema..."
	psql -h ${a} -p 5439 -U paraccel ${i} -f ${pdw}.sql -v ga=${i}_a -v gw=${i}_w -v gr=${i}_r -v go=${i}_o;

	echo "Running for ${i} canonical schema..."
	psql -h ${a} -p 5439 -U paraccel ${i} -f ${canonical}.sql -v ga=${i}_a -v gw=${i}_w -v gr=${i}_r -v go=${i}_o;

	echo "Running for ${i} schema permissions..."
	psql -h ${a} -p 5439 -U paraccel ${i} -c "ALTER SCHEMA ${pdw} OWNER TO ${i}_a ;
	ALTER SCHEMA ${canonical} OWNER TO ${i}_a ;
	GRANT ALL ON SCHEMA ${pdw} TO GROUP ${i}_a ;
	GRANT ALL ON SCHEMA ${canonical} TO GROUP ${i}_a ;
	GRANT USAGE ON SCHEMA ${pdw} TO GROUP ${i}_r ;
	GRANT USAGE ON SCHEMA ${canonical} TO GROUP ${i}_r ;
	GRANT USAGE ON SCHEMA ${pdw} TO GROUP ${i}_o ;
	GRANT USAGE ON SCHEMA ${canonical} TO GROUP ${i}_o ;
	GRANT USAGE ON SCHEMA ${pdw} TO GROUP ${i}_w ;
	GRANT USAGE ON SCHEMA ${canonical} TO GROUP ${i}_w ;
	"

	echo "Running for ${i} ACLs..."
	psql -h ${a} -p 5439 -U paraccel ${i} -f ${sn}_ACLs.sql -v ga=${i}_a -v gw=${i}_w -v gr=${i}_r -v go=${i}_o;
done

exit 0
