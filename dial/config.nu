use prelude.nu ["into iso-datestamp"]

# The dial config. Expects a `data/config.nu` file to exist.
#
# See the `data/config.example.nu`
export def main [] {
    open data/config.nuon
}

export def "team list" [] {
    main | get teams
}

export def "team list names" [] {
    team list | get name
}

# The list of organisations for the given team.
export def "team orgs" [team: string@"team list names"] {
    team list | where name == $team | get 0.orgs
}

# The list of repos for the given team.
export def "team repos" [team: string@"team list names"] {
    team list | where name == $team | get 0.repos
}

# The list of members for the given team.
export def "team members" [team: string@"team list names"] {
    team list | where name == $team | get 0.members
}

# Groups the team members into time windows where these members where part of the team. Windows are cropped by the given start and end date. 
export def "team time-windows" [
    start_date: datetime
    end_date: datetime
    team: string@"team list names"
] {
    let members = (team members $team)
    let orgs = (team orgs $team)

    let groups = $members
    | default $end_date end_date
    | where end_date >= $start_date
    | update start_date {|row| [$row.start_date $start_date] | math max }
    | update end_date {|row| [$row.end_date $end_date] | math min }
    | group-by --to-table {|row| $"($row.start_date | into iso-datestamp)/($row.end_date | into iso-datestamp)" }

    # Ensure the result is always a list.
    if ($groups | is-empty) {
        []
    } else {
        $groups
        | sort-by group
        | get items
        | each {
              {
                  start_date: $in.0.start_date
                  end_date: $in.0.end_date
                  members: ($in | select email github_handle)
                  orgs: $orgs
              }
          }
    }
}

# The list of Jira projects for the given team.
export def "team jira_projects" [team: string@"team list names"] {
    team list | where name == $team | get 0.jira_projects
}
