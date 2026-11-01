using Test
using Giac, GiacSlate
using SlateExtensionsBase: slate_render

@testset "GiacSlate" begin
    @testset "a derivation: notes as paragraphs, steps as aligned displays" begin
        @giac_var k a
        d = @derivation begin
            "Square **it**, with \$k\$ real:"
            k2 := k^2
            k^2 + 1
            "Then *again*:"
            @realign
            a + 1
        end
        html = slate_render(d).html
        @test startswith(html, "<div class=\"md giac-derivation\"")
        @test occursin("<p>Square <strong>it</strong>, with \$k\$ real:</p>", html)
        @test occursin("<p>Then <em>again</em>:</p>", html)
        @test count("\\begin{aligned}", html) == 2
        @test occursin("&amp;=", html)                                  # escaped for HTML
        # each display opens with the invisible row of its segment's widest sides, in display style
        @test count("\\hphantom{\\begin{matrix}\\displaystyle", html) == 2
    end

    @testset "a note's math is left as written" begin
        @test GiacSlate._note_html(raw"if $a < b$ and **c**") == raw"if $a &lt; b$ and <strong>c</strong>"
        @test GiacSlate._note_html(raw"$**x**$") == raw"$**x**$"
    end
end
