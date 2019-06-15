module RubybenchRunner
  class Configurations
    CONFIG_PATH = File.join(Dir.home, ".rubybench_runner_config")
    CONFIG_VERSION = 1
    MYSQL_MAPPING = {
      user: :username,
      dbname: :database
    }
    DEFAULTS = {
      postgres: {
        user: nil,
        dbname: "rubybench",
        host: nil,
        port: nil,
        password: nil
      },
      mysql2: {
        user: nil,
        dbname: "rubybench",
        host: nil,
        port: nil,
        password: nil
      },
      config_version: CONFIG_VERSION
    }
    def initialize(mysql_map: false)
      @mysql_map = mysql_map
      if !File.exists?(CONFIG_PATH)
        File.write(CONFIG_PATH, YAML.dump(DEFAULTS))
      end
    end

    def [](key)
      key = key.to_s
      result = config
      key.split(".").each do |k|
        result = result[k] || result[k.to_sym]
      end
      result
    end

    def config
      content = File.read(CONFIG_PATH)
      if content != @content
        @content = content
        @parsed = YAML.load(@content)
        if @mysql_map
          MYSQL_MAPPING.each do |old, new|
            next if !@parsed[:mysql2].key?(old)
            val = @parsed[:mysql2][old]
            @parsed[:mysql2][new] = val
            @parsed[:mysql2].delete(old)
          end
        end
      end
      @parsed
    end

    def config_changed?
      File.read(CONFIG_PATH) != YAML.dump(DEFAULTS)
    end
  end
end
