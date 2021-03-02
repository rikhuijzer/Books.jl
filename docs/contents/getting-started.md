# Getting started {#sec:getting-started} 

This package is still quite experimental.
If you copy over the files in `docs/` to somewhere on your pc and set up a Julia project, then serving a book should work if you run

```
julia --project -e 'using Books; serve()'
```

Otherwise, take a look at the `docs` folder in the [GitHub repository](https://github.com/rikhuijzer/Books.jl/tree/main/docs).
That folder contains a full example project.

## Pandoc files

This project includes some default templates and styles.
To override these, create one or more of the following files

- `pandoc/style.csl` - citation style
- `pandoc/style.css` - style sheet
- `pandoc/template.html` - HTML template
- `pandoc/template.tex` - PDF template