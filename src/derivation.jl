# ---------------------------------------------------------------------------
# Giac derivations in a notebook: notes as paragraphs, steps as centered display blocks whose `=`
# signs line up from block to block.
#
# KaTeX typesets math only, so a note can't wrap inside one display the way LaTeX's \intertext does
# in `align`. Here each note is a paragraph of the page and each run of steps a display of its own.
# Every display in an alignment segment has the same width: a first row holds the segment's widest
# left and right sides, invisible, and a negative gap takes that row's height back, so centering
# each display puts the `=` signs in one column. Elsewhere (a PDF, another frontend) a derivation
# shows in the forms Giac gives it.
# ---------------------------------------------------------------------------

function SlateExtensionsBase.slate_render(d::Giac.Derivation)
    parts = Giac.derivation_parts(d)
    sides = Dict{Int, Tuple{Vector{String}, Vector{String}}}()
    for p in parts
        haskey(p, :steps) || continue
        lefts, rights = get!(() -> (String[], String[]), sides, p.segment)
        append!(lefts, first.(p.steps))
        append!(rights, last.(p.steps))
    end
    pads = Dict(k => _derivation_pad(l, r) for (k, (l, r)) in sides)
    html = map(parts) do p
        haskey(p, :note) && return "<p>" * _note_html(p.note) * "</p>"
        body = join(("$l &= $r" for (l, r) in p.steps), " \\\\ ")
        return "<p>\$\$\\begin{aligned}" * _escape_html(pads[p.segment] * body) * "\\end{aligned}\$\$</p>"
    end
    # The `md` class and the 1rem base give it a markdown cell's typography: the same prose and math
    # sizes, where a cell's output area is otherwise set smaller.
    return html_fragment("<div class=\"md giac-derivation\" style=\"padding: 0; font-size: 1rem;\">" * join(html) * "</div>")
end

# The invisible first row of a display: the widest left and right sides, stacked. A matrix sets its
# cells in text style, smaller than the display style of the steps, hence `\displaystyle`.
function _derivation_pad(lefts, rights)
    stack(sides) = "\\begin{matrix}" * join(("\\displaystyle " * s for s in sides), " \\\\ ") * "\\end{matrix}"
    return "\\hphantom{" * stack(lefts) * "} & \\hphantom{{} = " * stack(rights) * "} \\\\[-1.5em] "
end

_escape_html(s) = replace(s, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")

# A note's markdown as HTML: `**bold**`, `*italic*` and `` `code` ``, with its `$…$` math left for the
# page to typeset.
function _note_html(md::AbstractString)
    out = IOBuffer()
    for m in eachmatch(r"\$\$.+?\$\$|\$[^$]+\$|[^$]+|\$", md)
        s = _escape_html(m.match)
        startswith(m.match, "\$") || (s = _inline_markdown(s))
        print(out, s)
    end
    return String(take!(out))
end

_inline_markdown(s) = foldl(replace, (r"\*\*(.+?)\*\*" => s"<strong>\1</strong>", r"\*(.+?)\*" => s"<em>\1</em>",
                                      r"`(.+?)`" => s"<code>\1</code>"); init = s)
