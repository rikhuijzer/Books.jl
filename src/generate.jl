
"""
    code_block(s)

Wrap `s` in a Markdown code block with triple backticks.
"""
code_block(s) = "```\n$s\n```\n"

"""
    output_block(s)

Wrap `s` in a Markdown code block with the language description "output".
"""
output_block(s) = "```output\n$s\n```\n"

function extract_codeblock_expr(s)
end

extract_expr_example() = """
    lorem
    ```jl
    foo(3)
    ```
    ```jl
    foo(3)
    bar
    ```
    ipsum `jl bar()` dolar
    """

"""
    extract_expr(s::AbstractString)::Vector

Returns the filenames mentioned in the `jl` code blocks.
Here, `s` is the contents of a Markdown file.

```jldoctest
julia> s = Books.extract_expr_example();

julia> Books.extract_expr(s)
3-element Vector{String}:
 "foo(3)"
 "foo(3)\\nbar"
 "bar()"
```
"""
function extract_expr(s::AbstractString)::Vector
    codeblock_pattern = r"```jl\s*([\w\W]*?)```"
    matches = eachmatch(codeblock_pattern, s)
    function clean(m)
        m = m[1]::SubString{String}
        m = strip(m)
        m = string(m)::String
    end
    from_codeblocks = clean.(matches)

    inline_pattern = r" `jl ([^`]*)`"
    matches = eachmatch(inline_pattern, s)
    from_inline = clean.(matches)
    exprs = [from_codeblocks; from_inline]

    function check_parse_errors(expr)
        try
            Meta.parse("begin $expr end")
        catch e
            error("Exception occured when trying to parse `$expr`")
        end
    end
    check_parse_errors.(exprs)
    exprs
end

"""
    caller_module()

Walks up the stacktrace to find the first module which is not Books.
Thanks to https://discourse.julialang.org/t/get-module-of-a-caller/11445/3
"""
function caller_module()
    s = stacktrace()
    for i in 1:10
        try
            M = s[i].linfo.linetable[1].module
            return M
        catch
        end
    end
    throw(ErrorException("Couldn't determine the module of the caller"))
end

remove_modules(expr) = replace(expr, r"^[A-Z][a-zA-Z]*\." => "")

"""
    method_name(expr::String)

Return file name for `expr`.
This is used for things like how to call an image file and a caption.

# Examples
```jldoctest
julia> Books.method_name("@some_macro(M.foo)")
"foo"

julia> Books.method_name("M.foo()")
"foo"

julia> Books.method_name("M.foo(3)")
"foo_3"

julia> Books.method_name("Options(foo(); caption='b')")
"Options_foo__captionis-b-"
```
"""
function method_name(expr::String)
    remove_macros(expr) = replace(expr, r"@[\w\_]*" => "")
    expr = remove_macros(expr)
    if startswith(expr, '(')
        expr = strip(expr, ['(', ')'])
    end
    expr = remove_modules(expr)
    expr = replace(expr, '(' => '_')
    expr = replace(expr, ')' => "")
    expr = replace(expr, ';' => "_")
    expr = replace(expr, " " => "")
    expr = replace(expr, '"' => "-")
    expr = replace(expr, '\'' => "-")
    expr = replace(expr, '=' => "is")
    expr = replace(expr, '.' => "")
    expr = strip(expr, '_')
end

"""
    escape_expr(expr::String)

Escape an expression to the corresponding path.
The logic in this method should match the logic in the Lua filter.
"""
function escape_expr(expr::String)
    n = 80
    escaped = n < length(expr) ? expr[1:n] : expr
    escaped = replace(escaped, r"([^a-zA-Z0-9]+)" => "_")
    joinpath(GENERATED_DIR, "$escaped.md")
end

function evaluate_and_write(M::Module, expr::String)
    path = escape_expr(expr)
    expr_info = replace(expr, '\n' => "\\n")
    println("Writing output of `$expr_info` to $path")

    ex = Meta.parse("begin $expr end")
    out = Core.eval(M, ex)
    out = convert_output(expr, path, out)
    out = string(out)::String
    write(path, out)

    nothing
end

function evaluate_and_write(f::Function)
    function_name = Base.nameof(f)
    expr = "$(function_name)()"
    path = escape_expr(expr)
    expr_info = replace(expr, '\n' => "\\n")
    println("Writing output of `$expr_info` to $path")
    out = f()
    out = convert_output(expr, path, out)
    out = string(out)::String
    write(path, out)

    nothing
end

function clean_stacktrace(stacktrace::String)
    lines = split(stacktrace, '\n')
    contains_books = [contains(l, "] top-level scope") for l in lines]
    i = findfirst(contains_books)
    lines = lines[1:i+5]
    lines = [lines; " [...]"]
    stacktrace = join(lines, '\n')
end

function report_error(expr, e)
    path = escape_expr(expr)
    # Source: Franklin.jl/src/eval/run.jl.
    exc, bt = last(Base.catch_stack())
    stacktrace = sprint(Base.showerror, exc, bt)::String
    stacktrace = clean_stacktrace(stacktrace)
    msg = """
        Failed to run:
        $expr

        Details:
        $stacktrace
        """
    @error msg
    write(path, code_block(msg))
end

"""
    evaluate_include(expr::String, M, fail_on_error::Bool)

For a `path` included in a Markdown file, run the corresponding function and write the output to `path`.
"""
function evaluate_include(expr::String, M, fail_on_error::Bool)
    if isnothing(M)
        # This code isn't really working.
        M = caller_module()
    end
    if fail_on_error
        evaluate_and_write(M, expr)
    else
        try
            evaluate_and_write(M, expr)
        catch e
            report_error(expr, e)
        end
    end
end

"""
    expand_path(p)

Expand path to allow an user to pass `index` instead of `contents/index.md` to `gen`.
Not allowing `index.md` because that is confusing with entr(f, ["contents"], [M]).
"""
function expand_path(p)
    joinpath("contents", "$p.md")
end

"""
    gen(paths::Vector; M=Main, fail_on_error=false, project="default")

Populate the files in `$(Books.GENERATED_DIR)/` by calling the required methods.
These methods are specified by the filename and will output to that filename.
This allows the user to easily link code blocks to code.
The methods are assumed to be in the module `M` of the caller.
Otherwise, specify another module `M`.
After calling the methods, this method will also call `html()` to update the site when
`call_html == true`.

!!! note

    If there is anthing that you want to have available when running the code blocks,
    just load them inside your REPL (module `Main`) and call `gen()`.
    For example, you can define `M = YourModule` to shorten calls to methods in your module.
"""

function gen(paths::Vector{String};
        M=Main, fail_on_error=false, project="default", call_html=true)

    mkpath(GENERATED_DIR)
    paths = [contains(dirname(p), "contents") ? p : expand_path(p) for p in paths]
    included_expr = vcat([extract_expr(read(p, String)) for p in paths]...)
    f(expr) = evaluate_include(expr, M, fail_on_error)
    foreach(f, included_expr)
    if call_html
        println("Updating html")
        html(; project)
    end
end

"""
    gen(path::AbstractString; kwargs...)

Convenience method for passing `path::AbstractString` instead of `paths::Vector`.
"""
function gen(path::AbstractString; kwargs...)
    path = string(path)::String
    gen([path]; kwargs...)
end

function gen(; M=Main, fail_on_error=false, project="default", call_html=true)
    paths = inputs(project)
    first_file = first(paths)
    if !isfile(first_file)
        error("Couldn't find $first_file. Is there a valid project in $(pwd())?")
    end
    gen(paths; M, fail_on_error, project, call_html)
end
