#!/bin/bash

set -e

# get issns used by our dois from bq and save them in the pg crossref_issn table

: ${DATABASE_URL:?environment variable must be set}

# extract the view to a temp table
# because views can't be extracted directly to files

echo extracting view to temp table

bq_temp_table="journals.tmp_crossref_issns_$RANDOM"

bq query \
    --headless --quiet \
    --project_id='unpaywall-bhd' \
    --use_legacy_sql=false \
    --destination_table=$bq_temp_table \
    --max_rows=0 \
    "select * from journals.crossref_issns;"

# extract the mapping file to CSV and delete the temp table

echo exporting temp table to gcs

gcs_csv="gs://unpaywall-grid/crossref-issns-$RANDOM.csv"

bq extract \
    --headless --quiet \
    --project_id='unpaywall-bhd' \
    --format=csv \
    $bq_temp_table \
    $gcs_csv

bq rm -f \
    --project_id='unpaywall-bhd' \
    $bq_temp_table

# download the CSV and delete the remote file

workdir=$(mktemp -d)
local_csv=$workdir/crossref-issns.csv

echo "downloading $gcs_csv -> $local_csv"
gsutil cp $gcs_csv $local_csv
gsutil rm $gcs_csv

# upsert journal table issnl to issn list mappings

echo updating pg crossref_issn table

sed "s|_ISSN_CSV_|$local_csv|" load-crossref-issns.sql | psql $DATABASE_URL
