module RubybenchRunner
  class RailsRunner < BaseRunner
    def command
      command = "RAILS_ENV=production #{super}"
      if require_db?
        command = "DATABASE_URL=#{database_url} #{command}"
      end
      command
    end

    def database_url
      return @db_url if @db_url
      raw_config = RubybenchRunner::Configurations.new
      config = OpenStruct.new(raw_config[opts.db.to_sym])
      url = "#{opts.db}://#{config.user}"
      url += ":#{config.password}" if config.password
      url += "@"
      if config.host && config.port
        url += "#{config.host}:#{config.port}"
      end
      url += "/#{config.dbname}"
      with_prep_statement = opts.wps == true
      url += "?prepared_statements=#{with_prep_statement}"
      @db_url = url
    end

    def setup_db
      return if !require_db?
      log("Checking database...")
      config = RubybenchRunner::Configurations.new(mysql_map: true)
      if opts.db == "postgres"
        require 'pg'
        conn_config = config["postgres"]
        rubybench_db = conn_config[:dbname]
        conn_config[:dbname] = "postgres"
        conn = PG.connect(conn_config)
        begin
          res = conn.exec("SELECT 1 FROM pg_database WHERE datname = '#{rubybench_db}'")
          if !res.first
            conn.exec("CREATE DATABASE #{rubybench_db}")
            log("Created PostgreSQL database with the name '#{rubybench_db}'")
          end
        ensure
          conn.close
        end
      elsif opts.db == "mysql2"
        require 'mysql2'
        conn_config = config["mysql2"]
        rubybench_db = conn_config[:database]
        conn_config[:database] = "mysql"
        client = Mysql2::Client.new(conn_config)
        begin
          res = client.query("SHOW DATABASES LIKE '#{rubybench_db}'")
          if !res.first
            client.query("CREATE DATABASE #{rubybench_db}")
            log("Created MySQL database with the name '#{rubybench_db}'")
          end
        ensure
          client.close
        end
      end
    end

    def benchmark_name
      @benchmark_name ||= "Rails"
    end

    def gemfile_content
      @gemfile_content ||= <<~GEMFILE
        source 'https://rubygems.org'

        gem 'rails', path: '#{@repo_path}'

        gem 'mysql2', '0.5.2'
        gem 'pg', '1.1.4'
        gem 'benchmark-ips', '~> 2.7.2'
        gem 'redis', '~> 4.1.2'
        gem 'puma', '~> 3.12.1'
      GEMFILE
    end

    def save_dir
      @save_dir ||= File.join(dest_dir, "rails")
    end

    def require_db?
      filename = @script_url.split("/")[-1]
      filename.match?(/activerecord|scaffold/)
    end
  end
end
