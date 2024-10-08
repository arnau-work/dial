use duckdb.nu

alias save-file = save
alias open-file = open


# Use `date to-weeknumber`.
def to-weeknumber [] {
    $in | format date "%V" | into int
}

# Convert text or datetime into an ISO weeknumber.
#
# ```nu
# "2024-08-05" | date to-weeknumber #=> 32
# ```
export def "date to-weeknumber" []: [string -> int, datetime -> int, list<string> -> list<int>, int -> int, list<int> -> list<int>] {
    let input = $in

    match ($input | describe) {
        "string" | "list<string>" => {
            $input | into datetime | to-weeknumber
        },
        "int" | "list<int>" => {
            $input | into datetime | to-weeknumber
        },
        "date" => {
            $input | to-weeknumber
        },
    }
}

export def "into iso-datestamp" []: [datetime -> string] {
    $in | format date "%F"
}

export def "into iso-timestamp" []: [datetime -> string] {
    $in | format date "%+"
}


# A wrapper for the std open to bring opening parquet files into scope.
export def open [
    --raw (-r)
    --help (-h)
    ...files
] {
    if $help {
        open-file --help
    }

    if $raw {
        open-file --raw ...$files
    }

    let parquet_files = $files | where { path parse | get extension | $in == "parquet" }
    let other_files = $files | where { path parse | get extension | $in != "parquet" }

    interleave { open-file ...$other_files } { $parquet_files
        | par-each {|file| duckdb open $file }
        | flatten
    }
}
