module RubybenchRunner
  # TODO: ideally those should be fetched from rubybench.org API
  CURRENT_PG_VERSION = "9.6"
  CURRENT_MYSQL_VERSION = "5.6.24"

  class DependenciesChecker
    def self.check(pg:, mysql:)
      check_pg if pg
      check_mysql if mysql
    end

    def self.check_pg
      config = RubybenchRunner::Configurations.new[:postgres]
      config = config.merge(dbname: "postgres")
      conn = PG.connect(config)
      begin
        output = conn.parameter_status("server_version")
        output =~ /^([\d.]+) \(/
        version = $1
        if version != CURRENT_PG_VERSION
          warn("PostgreSQL", version, CURRENT_PG_VERSION)
        end
      ensure
        conn.close
      end
    end

    def self.check_mysql
      config = RubybenchRunner::Configurations.new(mysql_map: true)[:mysql2]
      config = config.merge(database: "mysql")
      client = Mysql2::Client.new(config)
      begin
        version = client.info[:version]
        if version != CURRENT_MYSQL_VERSION
          warn("MySQL", version, CURRENT_MYSQL_VERSION)
        end
      ensure
        client.close
      end
    end

    def self.warn(program, installed, recommended)
      puts <<~ALERT
        Warning: rubybench.org is currently running version #{recommended} of #{program}, you're running version #{installed}.
      ALERT
    end
  end
end
