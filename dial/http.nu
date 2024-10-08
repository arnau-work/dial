# HTTP helpers, extending std http

# Composes a URL.
export def "url join" [path: string --query (-q): record] {
    let base_url = $in

    [
        ([$base_url $path] | path join)
        ($query | url build-query)
    ]
    | compact --empty
    | str join "?"
}

# Expects an input from a raw Link http header.
#
# This is a rather naive parser for IETF RFC 8288 Web Linking values.
#
# ## Example
#
# ```nu
# '<https://api.github.com/search/issues?q=repo%3Anushell%2Fnushell+type%3Apr+is%3Amerged+merged%3A%3E%3D2024-08-01&order=desc&per_page=2&page=2>; rel="next", <https://api.github.com/search/issues?q=repo%3Anushell%2Fnushell+type%3Apr+is%3Amerged+merged%3A%3E%3D2024-08-01&order=desc&per_page=2&page=42>; rel="last"' | http from link-header
# ```
export def "from link-header" [] {
    $in
    | split row ","
    | each { $in | str trim | parse "<{url}>; rel=\"{rel}\"" }
    | flatten
}

# Input expected to be a valid http response record as per `http get`.
export def "header pick" [header_name: string] {
    let response = $in

    $response.headers.response
    | where name == $header_name
    | if ($in | is-not-empty) { get 0.value } else { null }
}

# Attempts to find a link by rel (RFC 8288).
#
# input: A valid http response
#
# ## Example
#
# ```nu
# http get https://api.github.com/search/issues | http link "next"
# ```
export def link [rel: string] {
    let raw = $in | header pick "link"

    if ($raw | is-empty) { return null }
    
    $raw
    | from link-header
    | where rel == $rel
    | if ($in | is-not-empty) { get 0.url } else { null }
}


# Attempts to find the next URL provided via Web Linking (RFC 8288).
#
# input: A valid http response
#
# ## Example
#
# ```nu
# http get https://api.github.com/search/issues | http next
# ```
export def next [] {
    $in | link next
}

# Attempts to find the last URL provided via Web Linking (RFC 8288).
#
# input: A valid http response
#
# ## Example
#
# ```nu
# http get https://api.github.com/search/issues | http last
# ```
export def last [] {
    $in | link last
}

# Attempts to find the first URL provided via Web Linking (RFC 8288).
#
# input: A valid http response
#
# ## Example
#
# ```nu
# http get https://api.github.com/search/issues | http first
# ```
export def first [] {
    $in | link first
}

# Attempts to find the previous URL provided via Web Linking (RFC 8288).
#
# input: A valid http response
#
# ## Example
#
# ```nu
# http get https://api.github.com/search/issues | http prev
# ```
export def prev [] {
    $in | link prev
}



# Collects all available information from a HTTP response.
#
# NOTE: GitHub response assumed.
export def "ratelimit" [] {
    $in
    | get headers.response
    | where name =~ "^x-ratelimit"
    | update name { $in | parse "x-ratelimit-{name}" | get name.0 }
    | update value {|row|
          match $row.name {
              reset => ($row.value | into int | $in * 1_000_000_000 | into datetime)
              remaining | limit | used => ($row.value | into int)
              _ => $row.value
          }
      }
    | reduce -f {} {|row, acc| $acc | upsert $row.name $row.value }
}

# Checks whether there is allowance for another request.
#
# ```nu
# let rl = $res | http ratelimit
#
# if ($rl | http ratelimit check) { $url | github fetch }
# ```
export def "ratelimit check" []: [record -> any] {
    not ($in.reset > (date now))

}
