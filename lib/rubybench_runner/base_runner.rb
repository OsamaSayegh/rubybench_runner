module RubybenchRunner
  class ShellError < StandardError; end

  def self.run(repo, script, opts = {})
    SUPPORTED_REPOS.each do |name, klass|
      if repo == name.to_s
        klass.new(script, opts).run
        return
      end
    end
    raise "Unknown repo #{repo}"
  end

  class BaseRunner
    HELPERS_VERSION_FILE = "helpers_version"

    COPY_FOLDERS = %w{
      support
      rails
    }
    attr_reader :script_url, :repo_path, :opts

    DEFAULT_OPTS = {
      repeat_count: 1,
      quiet: false,
      fresh_run: false,
      skip_dependencies_check: false,
      cleanup: false,
      wps: false,
      round: 2
    }

    def initialize(script, opts = {})
      @script_name = script
      @opts = OpenStruct.new(DEFAULT_OPTS.merge(opts))
      @script_url = @opts.url || script_full_url(script)
      @results = []
      @error = nil
      @output = ""
    end

    def run
      set_repo_path
      cleanup(before: true)
      create_tmpdir
      check_dependencies
      write_gemfile
      bundle_install
      setup_db
      download_script
      run_benchmarks
      process_results
      print_results
    ensure
      cleanup(after: true)
    end

    def possible_repo_path
      File.join(Dir.home, benchmark_name.downcase)
    end

    def is_repo_path_valid?
      true
    end

    def set_repo_path
      name = benchmark_name.downcase
      from_opts = false
      if path = opts.send(name)
        from_opts = true
        @repo_path = path
      else
        @repo_path = possible_repo_path
        log("Running #{name} benchmark #{@script_name}: #{name} path is #{possible_repo_path}\n")
      end

      unless is_repo_path_valid?
        output = "Cannot find #{name} at #{@repo_path}."
        output += "Perhaps try:\n\nrubybench_runner run #{name}/#{@script_name} --#{name}=/path/to/#{name}" unless from_opts
        log(output, f: true)
        exit 1
      end
    end

    def dest_dir
      # directory where all helpers and gems will be installed/copied to
      @dest_dir ||= File.join(Dir.tmpdir, "rubybench_runner_tmp")
    end

    def create_tmpdir
      FileUtils.mkdir_p(dest_dir)
      copy_helpers(dest_dir)
    end

    def copy_helpers(dest)
      gem_helpers_version_path = File.join(__dir__, HELPERS_VERSION_FILE)
      current_helpers_version_path = File.join(dest, HELPERS_VERSION_FILE)
      if !File.exists?(current_helpers_version_path) ||
        File.read(gem_helpers_version_path) != File.read(current_helpers_version_path)
        FileUtils.cp(gem_helpers_version_path, current_helpers_version_path)
        COPY_FOLDERS.each do |folder|
          origin = File.join(__dir__, folder)
          destination = File.join(dest, folder)
          FileUtils.cp_r(origin, destination)
        end
      end
    end

    def save_dir
      raise "Override the `save_dir` method in your subclass #{self.class.name}"
    end

    def gemfile_content
      nil
    end

    def script_path
      @script_path ||= File.join(save_dir, "benchmarks")
    end

    def script_full_path
      @script_full_path ||= File.join(script_path, script_name)
    end

    def script_name
      "script.rb"
    end

    def command
      if without_bundle?
        "ruby #{script_name}"
      else
        "BUNDLE_GEMFILE=#{gemfile_location} bundle exec ruby #{script_name}"
      end
    end

    def benchmark_name
      raise "Override the `benchmark_name` method in your class"
    end

    def require_db?
      false
    end

    def check_dependencies
      return if opts.skip_dependencies_check || !require_db?

      if opts.db == "postgres"
        require_gem 'pg'
      elsif opts.db == "mysql2"
        require_gem 'mysql2'
      end

      log("Checking dependencies...")
      RubybenchRunner::DependenciesChecker.check(pg: opts.db == "postgres", mysql: opts.db == "mysql2")
    end

    def setup_db
      return if !require_db?

      log("Checking database...")
      config = RubybenchRunner::Configurations.new(mysql_map: true)
      if opts.db == "postgres"
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

    def run_benchmarks
      return if @error
      log("Running benchmarks...")
      Dir.chdir(script_path) do
        opts.repeat_count.times do |n|
          res, err = Open3.capture3(command)
          if err.size == 0
            @results[n] = res
            @results[n] = JSON.parse(res)
          else
            raise ShellError.new(err)
          end
        end
      end
    rescue => err
      @error = err
    end

    def process_results
      return if @error
      @results.map! do |res|
        res.each do |key, val|
          if Float === val
            res[key] = val.round(opts.round)
          end
        end
        res
      end

      @results.sort_by! do |res|
        res['iterations_per_second']
      end
    end

    def print_results
      if @error
        @output = <<~OUTPUT
          An error occurred while running the benchmarks:
          Error #{@error.class}: #{@error.message}
          Backtrace:
          #{@error.backtrace.join("\n")}
        OUTPUT
        if @results.size > 0
          @output += <<~OUTPUT
            ------
            Raw results until this error:
            #{@results}
          OUTPUT
        end
      else
        label = @results.first['label']
        version = @results.first['version']
        @output = "#{benchmark_name} version #{version}\n"
        @output += "Results (#{@results.size} runs):\n"
        @results.map!.with_index do |res, ind|
          res.delete('label')
          res.delete('version')
          { "run #{ind + 1}" => res }
        end
        @output += "\n"
        @output += @results.to_yaml.sub("---\n", "")
      end
      puts @output
    end

    def bundle_install
      return if without_bundle?

      log("Installing gems...")
      comm = "bundle install"
      if opts.db == "mysql2"
        comm += " --without postgres"
      elsif opts.db == "postgres"
        comm += " --without mysql"
      else
        comm += " --without mysql postgres"
      end
      comm += " > /dev/null 2>&1" if !opts.verbose
      Dir.chdir(File.dirname(gemfile_location)) do
        system(comm)
      end

      if require_db?
        Dir.chdir(File.join(dest_dir, "support", "setup")) do
          system(comm)
        end
      end
    end

    def download_script
      log("Downloading script...")
      content = open(script_url).read
      File.write(script_full_path, content)
    rescue OpenURI::HTTPError => e
      log("Script download failed #{script_url}", f: true)
      @error = e
    end

    def write_gemfile
      return if without_bundle?
      File.write(gemfile_location, gemfile_content)
    end

    private

    def log(msg, f: false)
      return if opts.quiet && !f
      puts msg
    end

    def without_bundle?
      !gemfile_content
    end

    def gemfile_location
      File.join(save_dir, "Gemfile")
    end

    def cleanup(before: false, after: false)
      FileUtils.rm_f(script_full_path)
      FileUtils.rm_rf(dest_dir) if (opts.fresh_run && before) || (opts.cleanup && after)
    end

    def script_full_url(script)
      if script !~ /\.rb$/
        script += ".rb"
      end
      "https://raw.githubusercontent.com/ruby-bench/ruby-bench-suite/master/#{benchmark_name.downcase}/benchmarks/#{script}"
    end

    # small hack for dynamically installing/requiring gems.
    # some benchmarks don't require db at all
    # so having mysql2 and pg in the gemspec file means
    # everyone must have postgres and mysql installed on
    # their machine in order to use this gem.
    # this hack allows us to not require mysql/postgres
    # until the user tries to run a benchmark that needs db.
    # --
    # source https://stackoverflow.com/a/36570445

    def require_gem(gem_name)
      require 'rubygems/commands/install_command'
      Gem::Specification::find_by_name(gem_name)
    rescue Gem::LoadError
      log("Installing the '#{opts.db}' gem...")
      install_gem(gem_name)
    ensure
      log("Using the '#{opts.db}' gem...")
      require gem_name
    end

    def install_gem(gem_name)
      cmd = Gem::Commands::InstallCommand.new
      cmd.handle_options [gem_name]     

      cmd.execute
    rescue Gem::SystemExitException => e
      puts "FAILURE: #{e.exit_code} -- #{e.message}" if e.exit_code != 0
    end
  end
end
