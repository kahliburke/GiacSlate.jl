module GiacSlate

# Autograder framework: structs, combinators, and HTML score cards.
include("grader.jl")
# Lesson content + reference solutions; registers its sections at load time.
include("laplace_lesson.jl")
# MathLive `<math-field>` → GiacExpr bridge (math-keyboard input).
include("mathfield.jl")
# giac"…" macro, gmath/gdisplay for markdown, and the editor's conversion bridge.
include("inline_math.jl")

# The notebook only ever calls these.
export grade, check, course_report, mathfield_to_giac, mathfield_boot,
       @giac_str, gmath, gdisplay, giac_src_to_tex, mathjson_to_giac_src, inline_math_boot

end # module GiacSlate
