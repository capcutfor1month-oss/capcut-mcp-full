defmodule CapcutMcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :capcut_mcp,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        ignore_warnings: ".dialyzer_ignore.exs",
        flags: [:error_handling, :unknown, :underspecs]
      ],
      test_coverage: [tool: ExCoveralls],
      releases: releases()
    ]
  end

  # A self-contained release is the supported way to run this as an MCP
  # stdio server: it boots in ~200ms with no compile step and no `_build`
  # lock (unlike `mix run`, which on a cold/external disk can take several
  # seconds and, when a client spawns several at once, serialises them on
  # the build lock). `vm.args.eex` sets `-noshell` so the BEAM's stdin is
  # delivered to `StdinReader` instead of an Erlang shell — identical
  # stdio semantics to `mix run --no-halt`, just fast and dependency-free.
  defp releases do
    [
      capcut_mcp: [
        include_executables_for: [:unix],
        applications: [capcut_mcp: :permanent]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {CapcutMcp.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 1.1", only: [:dev, :test]}
    ]
  end
end
