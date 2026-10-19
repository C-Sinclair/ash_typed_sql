import Config

config :library, ecto_repos: [Library.Repo], ash_domains: [Library]

config :ash, default_string_length_count: :codepoints

config :ash, :custom_expressions, [Library.Expressions.DaysOverdue]

import_config "#{config_env()}.exs"
