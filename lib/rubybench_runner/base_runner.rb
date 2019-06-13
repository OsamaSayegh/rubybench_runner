module RubybenchRunner
  def self.run(repo, script_url, repo_path, opts = {})
    if repo == "rails"
      klass = RubybenchRunner::RailsRunner
    else
      raise "Unknown repo #{repo}"
    end
    klass.new(script_url, repo_path, opts).run
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

    def initialize(url, repo_path, opts = {})
      @script_url = normalize_url(url)
      @repo_path = repo_path
      @opts = OpenStruct.new(DEFAULT_OPTS.merge(opts))
      @results = []
      @error = nil
      @output = ""
    end

    def run
      create_tmpdir
      cleanup(before: true)
      check_dependencies
      download_script
      write_gemfile
      bundle_install
      setup_db
      run_benchmarks
      process_results
      print_results
    ensure
      cleanup(after: true)
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
      return if opts.skip_dependencies_check
      log("Checking dependencies...")
      RubybenchRunner::DependenciesChecker.check
    end

    def setup_db
    end

    def run_benchmarks
      log("Running benchmarks...")
      Dir.chdir(script_path) do
        opts.repeat_count.times do |n|
          res = `#{command}`
          @results[n] = res
          @results[n] = JSON.parse(res)
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
          Error: #{@error.message}
          Backtrace:
          #{@error.backtrace.join("\n")}
          ------
          Raw results until this error:
          #{@results}
        OUTPUT
      else
        label = @results.first['label']
        version = @results.first['version']
        @output = "#{benchmark_name} version #{version}\n"
        @output += "Benchmark name: #{label}\n"
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
      comm += " > /dev/null 2>&1" if !opts.verbose
      Dir.chdir(File.dirname(gemfile_location)) do
        system(comm)
      end
      Dir.chdir(File.join(dest_dir, "support", "setup")) do
        system(comm)
      end
    end

    def download_script
      log("Downloading script...")
      content = open(script_url).read
      File.write(script_full_path, content)
    end

    def write_gemfile
      return if without_bundle?
      File.write(gemfile_location, gemfile_content)
    end

    private

    def log(msg)
      return if opts.quiet
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

    def normalize_url(url)
      if url =~ /^(https?:\/\/github.com)/
        url.sub($1, "https://raw.githubusercontent.com").sub("/blob", "")
      else
        url
      end
    end
  end
end
