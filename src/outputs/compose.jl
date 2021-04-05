using Compose

function write_svg(path, p, width, height)
    if isnothing(width)
        width = 6inch
    end
    if isnothing(height)
        height = 4inch
    end
    draw(SVG(path, width, height), p)
end

"""
    svg2png(svg_path, png_path)

Unlike ImageMagick, this program gets the text spacing right.
"""
function svg2png(svg_path, png_path)
    # 300 dpi should be sufficient for most journals, but shows aliasing.
    run(`cairosvg $svg_path -o $png_path --dpi 400`)
end

function convert_gadfly_output(path, out;
        caption=nothing, label=nothing, width=nothing, height=nothing)
    im_dir = joinpath(BUILD_DIR, "im")
    mkpath(im_dir)

    file = method_name(path)
    println("Writing plot images for $file")
    svg_filename = "$file.svg"
    svg_path = joinpath(im_dir, svg_filename)
    write_svg(svg_path, out, width, height)
    png_filename = "$file.png"
    png_path = joinpath(im_dir, png_filename)
    svg2png(svg_path, png_path)
    im_link = joinpath("im", svg_filename)
    caption, label = caption_label(path, caption, label)
    pandoc_image(file, png_path; caption, label)
end

function convert_output(path, out::Compose.Context; kwargs...)
    convert_gadfly_output(path, out; kwargs...)
end
