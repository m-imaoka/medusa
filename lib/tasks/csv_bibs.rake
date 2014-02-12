desc "bibs csv"
task :bibs_csv => :environment do
  ActiveRecord::Base.establish_connection :medusa_original
  
  ActiveRecord::Base.connection.execute("
    COPY(
      SELECT *
      FROM bibliographies
    )
    TO '/tmp/csv/bibliographies.csv'
    (FORMAT 'csv', HEADER);
  ")
  
  CSV.open("/tmp/csv/author_tests.csv", "w")
  
  bibliographies = CSV.table("/tmp/csv/bibliographies.csv")
  authors = CSV.table("/tmp/csv/author_tests.csv")
  
  bib_auth_array_all = bibliographies.map do |bib|
    bib[:authorlist].split(/, (?![A-Z]\.)/)
  end
  
  bib_auth_array_flat = bib_auth_array_all.flatten
  bib_auth_array_uniq_1 = bib_auth_array_flat.uniq
  
  bib_auth_array_uniq_2 = bib_auth_array_uniq_1.each do |authorlist|
    authorlist.gsub!(/and /, '')
  end
  
  bib_auth_array_uniq_3 = bib_auth_array_uniq_2.uniq
  
  today = Time.now.strftime("%Y-%m-%d %H:%M:%S.%6N")
  
  bib_array = bib_auth_array_uniq_3.map.with_index(1) do |auth, i|
    [i, auth, today, today]
  end
  
  bib_array.each do |bib|
    authors << bib
  end
  
  authors_csv = authors.to_csv(write_headers: false)
  
  File.open("/tmp/csv/authors.csv", "w") do |csv_file|
    csv_file.print("id,name,created_at,updated_at\n")
    csv_file.print(authors_csv)
  end
  
  FileUtils.rm("/tmp/csv/author_tests.csv")
  
  FileUtils.rm("/tmp/csv/bibliographies.csv")
  
  ActiveRecord::Base.connection.execute("
    COPY(
      SELECT
        id,
        entry_type,
        abbreviation,
        publisher as name,
        journal,
        year,
        volume,
        number,
        series as pages,
        month,
        note,
        key,
        link_url,
        doi,
        created_at,
        updated_at
      FROM bibliographies
      ORDER BY id
    )
    TO '/tmp/csv/bibs.csv'
    (FORMAT 'csv', HEADER);
  ")
  
  ActiveRecord::Base.establish_connection :development
  
  ActiveRecord::Base.connection.execute("
    COPY authors
    FROM '/tmp/csv/authors.csv'
    WITH CSV HEADER
  ")
  
  ActiveRecord::Base.connection.execute("
    COPY bibs
    FROM '/tmp/csv/bibs.csv'
    WITH CSV HEADER
  ")
  
  max_next_author_id = ActiveRecord::Base.connection.select_value("
    SELECT MAX(id)
    FROM authors
  ").to_i
  
  max_next_bib_id = ActiveRecord::Base.connection.select_value("
    SELECT MAX(id)
    FROM bibs
  ").to_i
  
  ActiveRecord::Base.connection.execute("
    SELECT setval('authors_id_seq', #{max_next_author_id})
  ")
  
  ActiveRecord::Base.connection.execute("
    SELECT setval('bibs_id_seq', #{max_next_bib_id})
  ")
  
end