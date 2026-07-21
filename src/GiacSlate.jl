module GiacSlate

# The lean Slate extension SDK — to_widget/auto_widget (the typed @bind seam), required_assets +
# __slate_frontend (lazy front-end delivery). GiacSlate depends only on this, never on KaimonSlate.
using SlateExtensionsBase

# Autograder framework: structs, combinators, and HTML score cards.
include("grader.jl")
# Lesson content + reference solutions; registers its sections at load time.
include("laplace_lesson.jl")
# MathLive `<math-field>` → GiacExpr bridge (math-keyboard input).
include("mathfield.jl")
# giac"…" macro, gmath/gdisplay for markdown, and the editor's conversion bridge.
include("inline_math.jl")

# The notebook only ever calls these. The front-end (the `Mathfield` renderer + the inline-math editor
# extension + its giac bridge handlers) wires itself up on `using GiacSlate` — no boot cell, no exports.
export grade, check, course_report, Mathfield, mathfield_to_giac,
       @giac_str, gmath, gdisplay, giac_src_to_tex, mathjson_to_giac_src

end # module GiacSlate
