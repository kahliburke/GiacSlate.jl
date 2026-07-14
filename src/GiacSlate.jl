module GiacSlate

# Autograder framework: structs, combinators, and HTML score cards.
include("grader.jl")
# Lesson content + reference solutions; registers its sections at load time.
include("laplace_lesson.jl")
# MathLive `<math-field>` → GiacExpr bridge (math-keyboard input).
include("mathfield.jl")

# The notebook only ever calls these.
export grade, check, course_report, mathfield_to_giac, mathfield_boot

end # module GiacSlate
