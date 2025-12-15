using SMLMView
using Documenter

DocMeta.setdocmeta!(SMLMView, :DocTestSetup, :(using SMLMView); recursive=true)

makedocs(;
    modules=[SMLMView],
    authors="klidke@unm.edu",
    sitename="SMLMView.jl",
    format=Documenter.HTML(;
        canonical="https://JuliaSMLM.github.io/SMLMView.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Examples" => "examples.md",
        "API Reference" => "api.md",
    ],
    warnonly=[:missing_docs],  # Allow internal functions to have docstrings without being in manual
)

deploydocs(;
    repo="github.com/JuliaSMLM/SMLMView.jl",
    devbranch="main",
)
