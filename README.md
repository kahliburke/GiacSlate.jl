# GiacSlate.jl

GiacSlate is a Julia package that integrates [Giac.jl](https://github.com/s-celles/Giac.jl) with Slate. It builds its `@bind` control and front-end boot against the lean Slate extension SDK (`SlateExtensionsBase`).

## Installation

GiacSlate isn't registered yet, so install it directly from the repository. From the Pkg REPL (press `]`):

```julia-repl
pkg> add https://github.com/kahliburke/GiacSlate.jl
```

*(Once GiacSlate is registered, `pkg> add GiacSlate` will be the one-liner.)*

## Running the Notebooks

The `notebooks/` directory contains interactive [Kaimon Slate](https://github.com/kahliburke/KaimonSlate.jl) notebooks that demonstrate Giac.jl's symbolic capabilities and GiacSlate's features.

To run them, ensure you have the `slate` CLI installed and run:

```sh
git clone https://github.com/kahliburke/GiacSlate.jl.git
cd GiacSlate.jl
slate notebooks/giac_intro.jl
```

- `giac_intro.jl`: An introduction to symbolic computation with Giac.jl, featuring calculus, linear algebra, and interactive Taylor series.
- `giac_tour.jl`: A comprehensive tour of the Xcas computer algebra engine, driven through live math fields.
- `laplace_lesson.jl`: An interactive physics lesson on the Laplace transform with self-grading exercises.
- `custom_controls.jl`: A playground for custom Slate widget plugins, experimenting with inline math fields.

## Math Input

GiacSlate provides live, interactive math fields powered by **MathLive <math-field>**. You can insert these math fields into Slate notebooks using the `giac"..."` string macro in code cells or embedded directly in Markdown prose. It provides a visual math keyboard and renders results seamlessly as typeset mathematics.

