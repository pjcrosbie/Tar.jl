"""
The `Header` type is a struct representing the essential metadata for a single
record in a tar file with this definition:

    struct Header
        path :: String # path relative to the root
        type :: Symbol # type indicator (see below)
        mode :: UInt16 # mode/permissions (best viewed in octal)
        size :: Int64  # size of record data in bytes
        link :: String # target path of a symlink
    end

Types are represented with the following symbols: `file`, `hardlink`, `symlink`,
`chardev`, `blockdev`, `directory`, `fifo`, or for unknown types, the typeflag
character as a symbol. Note that [`extract`](@ref) refuses to extract records
types other than `file`, `symlink` and `directory`; [`list`](@ref) will only
list other kinds of records if called with `strict=false`.

The tar format includes various other metadata about records, including user and
group IDs, user and group names, and timestamps. The `Tar` package, by design,
completely ignores these. When creating tar files, these fields are always set
to zero/empty. When reading tar files, these fields are ignored aside from
verifying header checksums for each header record for all fields.
"""
struct Header
    path::String
    type::Symbol
    mode::UInt16
    size::Int64
    link::String
end

function Base.show(io::IO, hdr::Header)
    show(io, Header)
    print(io, "(")
    show(io, hdr.path)
    print(io, ", ")
    show(io, hdr.type)
    print(io, ", 0o", string(hdr.mode, base=8, pad=3), ", ")
    show(io, hdr.size)
    print(io, ", ")
    show(io, hdr.link)
    print(io, ")")
end

const TYPE_SYMBOLS = (
    '0'  => :file,
    '\0' => :file, # legacy encoding
    '1'  => :hardlink,
    '2'  => :symlink,
    '3'  => :chardev,
    '4'  => :blockdev,
    '5'  => :directory,
    '6'  => :fifo,
)

function to_symbolic_type(type::Char)
    for (t, s) in TYPE_SYMBOLS
        type == t && return s
    end
    isascii(type) ||
        error("invalid type flag: $(repr(type))")
    return Symbol(type)
end

function from_symbolic_type(sym::Symbol)
    for (t, s) in TYPE_SYMBOLS
        sym == s && return t
    end
    str = String(sym)
    ncodeunits(str) == 1 && isascii(str[1]) ||
        throw(ArgumentError("invalid type symbol: $(repr(sym))"))
    return str[1]
end

function check_header(hdr::Header)
    errors = String[]
    err(e::String) = push!(errors, e)

    # error checks
    isempty(hdr.path) &&
        err("path is empty")
    0x0 in codeunits(hdr.path) &&
        err("path contains NUL bytes")
    0x0 in codeunits(hdr.link) &&
        err("link contains NUL bytes")
    !isempty(hdr.path) && hdr.path[1] == '/' &&
        err("path is absolute")
    occursin(r"(^|/)\.\.(/|$)", hdr.path) &&
        err("path contains '..' component")
    hdr.type in (:file, :symlink, :directory) ||
        err("unsupported file type")
    hdr.type ∉ (:hardlink, :symlink) && !isempty(hdr.link) &&
        err("non-link with link path")
    hdr.type == :symlink && hdr.size != 0 &&
        err("symlink with non-zero size")
    hdr.type == :directory && hdr.size != 0 &&
        err("directory with non-zero size")
    hdr.type != :directory && endswith(hdr.path, "/") &&
       err("non-directory path ending with '/'")
    hdr.type != :directory && (hdr.path == "." || endswith(hdr.path, "/.")) &&
       err("non-directory path ending with '.' component")
    hdr.size < 0 &&
       err("negative file size")
    isempty(errors) && return

    # contruct error message
    if length(errors) == 1
        msg = errors[1] * "\n"
    else
        msg = "tar header with multiple errors:\n"
        for e in sort!(errors)
            msg *= " * $e\n"
        end
    end
    msg *= repr(hdr)
    error(msg)
end
