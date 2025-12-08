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
    ],
)

deploydocs(;
    repo="github.com/JuliaSMLM/SMLMView.jl",
    devbranch="main",
)
