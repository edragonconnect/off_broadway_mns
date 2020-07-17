defmodule OffBroadwayMns.MixProject do
  use Mix.Project

  def project do
    [
      app: :off_broadway_mns,
      # same as broadway
      version: "0.1.0",
      elixir: "~> 1.8",
      name: "OffBroadwayMNS",
      description: "A Aliyun MNS connector for Broadway",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:broadway, "0.6.1"},
      {:gen_state_machine, "~> 2.1"},
      {:ex_aliyun_mns, "~> 1.0"}
    ]
  end
end
