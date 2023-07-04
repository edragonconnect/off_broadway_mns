defmodule OffBroadwayMns.MixProject do
  use Mix.Project

  @app :off_broadway_mns
  @source_url "https://github.com/edragonconnect/off_broadway_mns"

  def project do
    [
      app: @app,
      # same as broadway
      version: "1.0.7",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:broadway, "~> 1.0"},
      {:ex_aliyun_mns, "~> 1.2"},
      {:ex_doc, ">= 0.0.0", only: [:docs, :dev], runtime: false}
    ]
  end
  defp docs do
    [
      extras: [
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      formatters: ["html"],
      formatter_opts: [gfm: true]
    ]
  end

  defp package do
    [
      name: "off_broadway_mns",
      description: "A Aliyun MNS connector for Broadway",
      files: ["lib", "mix.exs", "README.md", "LICENSE.md"],
      maintainers: ["feng19"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
