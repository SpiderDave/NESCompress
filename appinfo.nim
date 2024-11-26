const version = "v" & CompileDate[0..3] & "." & CompileDate[5..6] & "." & CompileDate[8..9]

type
    App* = object
        name*: string
        version*: string = version
        author*: string
        url*: string
        date*: string = CompileDate
        time*: string = CompileTime
        description*: string
        stage*: string = "Prerelease"
        nimVersion*: string = NimVersion

proc info*(app: App): string =
    return app.name & " " & app.version & "-" & app.stage & " by " & app.author & " (" & app.url & ")"

proc releaseTag*(app: App): string =
    return app.name & " " & app.version & "-" & app.stage