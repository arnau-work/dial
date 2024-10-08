# Interactions with GitHub


use ./completer.nu
use prelude.nu ["into iso-datestamp"]
use ./error.nu *
use ./token.nu
use ./http.nu


def base-url [] {
    "https://api.github.com"
}

# Composes a token for the GitHub API.
def credentials [] {
    let token = try-env GITHUB_TOKEN

    token read $token
}

# Requests something from the GitHub API.
#
# Response notes:
#
# x-ratelimit-reset * 1_000_000_000 | into datetime
# x-ratelimit-remaining
export def "fetch" []: [string -> table] {
    let url = $in
    let token = credentials
    let headers = {
        Accept: "application/vnd.github+json"
        X-GitHub-Api-Version: "2022-11-28"
        Authorization: $"Bearer ($token)"
    }

    http get --full --allow-errors --headers $headers $url 
}

export def "rate-limit" [] {
    base-url
    | http url join "rate_limit"
    | fetch
}

# Converts record into search query string.
# Similar to `url build-query` but for search queries in GitHub.
export def "search build-query" []: [record -> string] {
    $in
    | items {|key, value|
          match ($value | describe --detailed | get type) {
              list => ($value | each { $"($key):($in)" })
              string => $"($key):($value)"
              $ty => (fail $"($ty) is not supported in search queries.")
          }
      }
    | flatten
    | str join " "
}

# Fetches a list page and provides the result and the URL to the next page.
#
# To be used with `generate`. Most likely you want to use `fetch all`
def "fetch page" [] {
    let input = $in

    if (($input.url | is-not-empty) and ($input.allowance > 0)) {
        let res = $input.url | fetch

        if ($res.status != 200) {
            return {
                out: {
                    status: $res.status
                    url: $input.url
                    error: $res.body
                }
                next: null
            }
        }

        let out = {
            status: $res.status
            ratelimit: ($res | http ratelimit)
            url: $input.url
            next_url: ($res | http next)
            data: $res.body
        }

        print $out

        {out: $out, next: {url: $out.next_url, allowance: $out.ratelimit.remaining}}
    }
}

# Fetches all pages from a starting URL.
export def "fetch all" [
    resource: string@"completer gh_ratelimit_resources" # A GitHub rate limit resource type.
]: [string -> table] {
    let url = $in
    let allowance = (rate-limit | get body.resources | get $resource | get remaining)
    let input = {
        allowance: $allowance
        url: $url
    }

    generate {fetch page} $input
}


# Search issues and pull requests.
#
# See: https://docs.github.com/en/rest/search/search?apiVersion=2022-11-28#search-issues-and-pull-requests
export def "search" [
    query: record # A record containing the query.
    --direction: string@"completer pr_direction" = desc
    --per-page: int = 100
    --page: int = 1
] {
    let query = {
        q: ($query | search build-query)
        order: $direction
        per_page: $per_page
        page: $page
    }
     
    base-url
    | http url join -q $query $"search/issues"
    | fetch all "search"
}

export def "pull-request normalise" [] {
    $in
    | flatten
    | insert repository {|row|
          $row.repository_url
          | parse --regex '(?<repo>[^\/]+\/[^\/]+)$'
          | get repo.0
      }
    | insert creator { get user.login }
    | rename --column {
          number: id
          title: summary
          created_at: creation_date
          closed_at: resolution_date
      }
    | select id repository summary creator creation_date resolution_date timeline_url
    | insert source "github"
}

# Retrieves the list of Pull Requests for the given query.
export def "pull-request fetch" [
    query: record        # Arbitrary search query.
    --direction: string@"completer pr_direction" = desc
    --per-page: int = 100
    --page: int = 1
] {
    let query = {
        type: pr
    } | merge $query

    search --direction $direction --per-page $per_page --page $page $query
}

# Expects a fully qualified timeline URL.
export def "pull-request timeline fetch" [] {
    $in | fetch all "core"
}

const allowlist_events = [
    assigned        
    closed
    commented
    # committed # XXX: This event is massively different from the rest.
    convert_to_draft
    merged
    ready_for_review
    renamed
    reopened
    review_dismissed
    review_requested
    review_request_removed
    reviewed
    unassigned
]


export def "pull-request timeline normalise" [] {
    $in
    | get data
    | flatten
    | reject id?
    | upsert source github
    | where { $in.event in $allowlist_events }
    | upsert actor {|row|
          match $row.event {
              committed => $row.author?.email
              commented | reviewed => $row.user?.login
              _ => $row.actor?.login
          }
      }
    | insert timestamp {|row|
          match $row.event {
              committed => $row.author?.date
              reviewed => $row.submitted_at
              _ => $row.created_at
          }
      }
    | rename --column {node_id: id}
    | select id changeset_id repository timestamp event actor url? source
}
