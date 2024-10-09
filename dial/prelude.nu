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


export def "into days" [] {
    $in
    | into int
    | $in / 1_000_000_000
    | $in / 86_400
}

export def "date weekday" [] {
    $in
    | format date "%u"
    | into int
}

# Calculates the number of working days between two dates, excluding weekends.
export def weekdays [start_date: datetime, end_date: datetime] {
    let days = (($end_date - $start_date) + 1day) | into days

    let full_weeks = $days // 7
    # number of weekdays in full weeks
    let weekdays_in_full_weeks = $full_weeks * 5

    # number of weekdays in partial weeks
    let remaining_days = $days mod 7

    # number of weekend days in the remaining partial weeks
    mut weekend_days = 0
    let start_weekday = $start_date | date weekday
    mut end_weekday = $end_date | date weekday

    if ($days > ($full_weeks * 7)) {
      if ($end_weekday < $start_weekday) {
        $end_weekday += 7
      }

      if ($start_weekday <= 6) {
        if ($end_weekday >= 7) { # saturday and sunday in the remainder
          $weekend_days += 2
        } else if ($end_weekday >= 6) { # saturday in the remainder
          $weekend_days += 1
        }
      } else if ($start_weekday <= 7 and $end_weekday >= 7) { # sunday in the remainder
        $weekend_days += 1
      }
    }

    # Add the number of weekdays in full weeks and partial weeks
    let total_weekdays = $weekdays_in_full_weeks + $remaining_days - $weekend_days

    $total_weekdays
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
