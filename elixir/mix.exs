defmodule Elixir.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_diagnose,
      version: "0.1.0",
      elixir: ">= 1.9.0",
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

  defp integration_path do
    path = System.get_env("ELIXIR_INTEGRATION_PATH", "../../..")
    Path.absname(path, "../")
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.2"},
      {:appsignal, path: integration_path()}
    ]
  end
end
