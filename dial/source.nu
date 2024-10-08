# Managing data fetched from sources such as GitHub.
use config.nu *
use prelude.nu ["into iso-datestamp", "into iso-timestamp"]
use github.nu
use jira.nu
use duckdb.nu
use storage.nu


# Fetches changesets for a single team time-window (see `team time-window`).
export def "changeset fetch-window" [window: record] {
    let orgs = $window.orgs
    let start_date = ($window.start_date | into iso-datestamp)
    let end_date = ($window.end_date | into iso-datestamp)

    let handles = ($window.members | get github_handle)
    let query = {
        org: $orgs
        author: $handles
        is: merged
        merged: $"($start_date)..($end_date)"
    }

    let res = github pull-request fetch $query

    # Soft abort if at least one request failed.
    # TODO: review fail path for 422
    if ($res | where status != 200 | is-not-empty) {
        return $res
    }

    $res
    | get data.items
    | github pull-request normalise
    | tee {
          if ($in | is-not-empty) { $in | storage save changeset }
      }
    | do {
          let items = $in

          {
              table: changeset
              count: ($items | length)
              start_date: $window.start_date
              end_date: $window.end_date
          }
      }
}

# Fetches merged GitHub Pull Request for the team organisations for the given date
# range. The result is persisted in `changeset`.
export def "changeset fetch" [start_date: datetime, end_date: datetime, team: string@"team list names"] {
    team time-windows $start_date $end_date $team
    | each {|window| changeset fetch-window $window }
}

# Fetches the timelines for any changeset stored for the given date range.
# The result is persisted in `changeset_timeline`.
export def "changeset timeline fetch" [start_date: datetime, end_date: datetime] {
    let start_date = ($start_date | into iso-datestamp)
    let end_date = ($end_date | into iso-datestamp)

    storage query $"select * from changeset where resolution_date >= date '($start_date)' and resolution_date <= date '($end_date)'"
    | each {|row|
          $row.timeline_url
          | github pull-request timeline fetch
          | insert data.changeset_id $row.id
          | insert data.repository $row.repository
          | github pull-request timeline normalise
          | tee { if ($in | is-not-empty) { $in | storage save changeset_event } }
          | do {
                let items = $in

                {
                    table: changeset_event
                    count: ($items | length)
                    start_date: $start_date
                    end_date: $end_date
                }
            }
      }
}


# Fetch Jira tickets for the given date range and team members. The result is persisted in `ticket`.
#
# ```nu
# dial ticket fetch 2024-09-23 2024-09-27 red-onions
# ```
export def "ticket fetch" [start_date: datetime, end_date: datetime, team: string@"team list names"] {
    let emails = team members $team | get email

    let res = jira ticket fetch $start_date $end_date $emails

    $res
    | where status == 200
    | get data?
    | flatten
    | jira ticket flatten
    | tee { if ($in | is-not-empty) { $in | storage save ticket } }
    | do {
          let items = $in

          {
              table: ticket
              count: ($items | length)
              start_date: $start_date
              end_date: $end_date
              errors: ($res | where status != 200)
          }
      }
}


export def "ticket timeline fetch" [start_date: datetime, end_date: datetime] {
    let start_date = $start_date | format date "%F"
    let end_date = $end_date | format date "%F"

    storage query $"select * from ticket where resolution_date >= date '($start_date)' and resolution_date <= date '($end_date)'"
    | par-each {|row|
          let res = jira changelog fetch $row.key

          if ($res | where status != 200 | is-empty) {
              $res
              | get data?
              | flatten
              | jira changelog flatten
          } else {
              fail $"Failed to fetch ($row.key)"
          }
      }
    | flatten
    | tee { if ($in | is-not-empty) { $in | storage save ticket_status } }
    | do {
          let items = $in

          {
              table: ticket_status
              count: ($items | length)
              start_date: $start_date
              end_date: $end_date
          }
      }
}
