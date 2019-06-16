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
      url += "@#{config.host}" if config.host
      url += ":#{config.port}" if config.port
      url += "/#{config.dbname}"
      with_prep_statement = opts.wps == true
      url += "?prepared_statements=#{with_prep_statement}"
      @db_url = url
    end

    def benchmark_name
      @benchmark_name ||= "Rails"
    end

    def gemfile_content
      @gemfile_content ||= <<~GEMFILE
        source 'https://rubygems.org'

        gem 'rails', path: '#{@repo_path}'

        group :mysql do
          gem 'mysql2', '0.5.2'
        end
        group :postgres do
          gem 'pg', '1.1.4'
        end
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
      res = filename.match?(/activerecord|scaffold/)
      if res && !opts.db
        puts "This benchmark requires database to run. Please specify the `--db` option (see --help for details)"
        exit 1
      end
      res
    end
  end
end
