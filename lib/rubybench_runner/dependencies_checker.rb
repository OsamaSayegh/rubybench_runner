module RubybenchRunner
  # TODO: ideally those should be fetched from rubybench.org API
  CURRENT_PG_VERSION = "9.6"
  CURRENT_MYSQL_VERSION = "5.6.24"

  class MissingDependency < StandardError; end
  class DependenciesChecker
    def self.check(pg:, mysql2:)
      check_pg if pg
      check_mysql if mysql2
    end

    def self.check_pg
      output = `pg_config --version`.strip
      output =~ /^PostgreSQL ([\d.]+)/
      version = $1
      if version != CURRENT_PG_VERSION
        warn("PostgreSQL", version, CURRENT_PG_VERSION)
      end
    rescue Errno::ENOENT
      raise MissingDependency.new("Postgres doesn't seem to be installed on your system. Please install it and run the benchmarks again")
    end

    def self.check_mysql
      version = `mysql_config --version`.strip
      if version != CURRENT_MYSQL_VERSION
        warn("MySQL", version, CURRENT_MYSQL_VERSION)
      end
    rescue Errno::ENOENT
      raise MissingDependency.new("MySQL doesn't seem to be installed on your system. Please install it and run the benchmarks again")
    end

    def self.warn(program, installed, recommended)
      puts <<~ALERT
        Warning: rubybench.org is currently running version #{recommended} of #{program}, you're running version #{installed}.
      ALERT
    end
  end
end
