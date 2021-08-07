---
title: "Personal psql configuration"
date:  "2021-08-07"
tags: ["postgresql", "psql", "psqlrc", "cli"]
---

## Official CLI client

[PostgreSQL](https://www.postgresql.org/) is by far my most favourite relational database engine.
It's very powerful, extensible, widely adopted by cloud providers, and totally FOSS.
There are many [client tools](https://wiki.postgresql.org/wiki/PostgreSQL_Clients) that let you interact with Postgres,
but I usually prefer to default to official software when I have so many choices. That way, I know the tool will be compatible, and battle tested by a huge community. In case of Postgres, the official CLI tool is [psql](https://www.postgresql.org/docs/current/app-psql.html), which is usually distributed with every installation.

## Customisation

Postgres CLI client, the __psql__ can be customised by creating a _.psqlrc_ file in the user's home directory.
In this section, I will walk you through my personal settings and try to explain them in a clear way.

You will see few different ways of changing the settings, so it's important to understand what each of them does:
- `\set [name [value [...]]]` -  Sets the __psql__ variable `name` to `value`.
- `\pset [option [value]]` - This command sets options affecting the output of query result tables.
- `\setenv name [value]` - Sets the environment variable `name` to `value`, or if the value is not supplied, unsets the environment variable.
- `set [SESSION | LOCAL] configuration_parameter {TO | =} {value | 'value' | DEFAULT}` - set a __Postgres__ runtime variable.

Additionally, it is also possible to print text with `\echo` command.

Hopefully that will avoid some confusion in the next section. If you still have some doubts, consult the official documentation for psql
and [Postgres set command](https://www.postgresql.org/docs/current/sql-set.html).

### Prompt look

Psql uses the `PROMPT[1|2|3]` variables to set the look of the command prompt.
`PROMPT1` is the default, normal prompt; `PROMPT2` is for multiline input, and `PROMPT3` is used for `COPY FROM STDIN` commands.
See [prompting](https://www.postgresql.org/docs/current/app-psql.html#APP-PSQL-PROMPTING) for further details.

```sql
-- [hostname] @ [database] [connection status] [transaction status] >
\set PROMPT1 '%[%033[1m%]%M %n@%/%R%~%x%[%033[0m%]%> '
\set PROMPT2 '[more] %R > '
```

### Query result display

Following settings will result in more verbose query results and error messages. I also like to change the default value of `null` - since most of the console hosts support Unicode characters, nothing should stop you from using a special character like `Ф` or your favourite emoji here. 

```sql
\set VERBOSITY verbose
\pset null '[null]'
\pset linestyle 'unicode'
\pset unicode_border_linestyle single
\pset unicode_column_linestyle single
\pset unicode_header_linestyle single
set intervalstyle to 'postgres_verbose';
```

I also customised the look of pager, for the long query results: 

```sql
\setenv LESS '-iMFXSx4R'
```

Automatically switch between table/expanded table format.

```sql
\pset expanded auto
\pset columns 120
```

### Transactions behaviour

With the following options, psql will know to stop executing your script on first error and will issue an interactive rollback, by creating an implicit SAVEPOINT.
This setting is somewhat similar to `set -e` in bash scripts.

```sql
\set ON_ERROR_STOP on
\set ON_ERROR_ROLLBACK interactive
```

### Command history

Psql also lets you customise the way it stores the command history.
I've set mine to ignore duplicate commands (keeps history file lean),
and store commands issued against different databases in separate files.

Second setting is quite useful if you're developing multiple db schemas, with unique tables/namespaces. However, if you're a db admin and you run same or similar queries against different databases, you might want to omit this customisation.

```sql
\set HISTCONTROL ignoredups
\set HISTFILE ~/.psql_history- :DBNAME
```

### Aliases

Lastly, you can define aliases for common SQL queries. You run an aliased query by typing `:alias` in the CLI. Here are some of my simple aliases:   

```sql
-- > :version -- gives psql version output
\set version    'SELECT version();'

-- > :extensions  -- lists all available extensions
\set extensions 'SELECT * FROM pg_available_extensions;'

-- > :settings  -- shows all psql settings and their values
\set settings   'SELECT name, setting,unit,context FROM pg_settings;'

-- > :uptime  -- how long has this thing been up?
\set uptime     'SELECT now() - pg_postmaster_start_time() AS uptime;'
```

### Complete example

<details>
<summary>Click to expand .psqlrc config</summary>

```sql
-- PostgreSQL command line tool settings.

-- Be quiet at startup.
\set QUIET 1

-- Set app name.
set application_name to 'me@psql';

-- Default prompt look: [hostname] @ [database] [connection status] [transaction status] >
\set PROMPT1 '%[%033[1m%]%M %n@%/%R%~%x%[%033[0m%]%> '
-- Multi-line prompt look.
\set PROMPT2 '[more] %R > '

-- Various display settings.
\set VERBOSITY verbose
\pset null '[null]'
\pset linestyle 'unicode'
\pset unicode_border_linestyle single
\pset unicode_column_linestyle single
\pset unicode_header_linestyle single
set intervalstyle to 'postgres_verbose';

-- Customise pager
\setenv LESS '-iMFXSx4R'

-- Automatically switch between table/expanded table format.
\pset expanded auto
\pset columns 120

-- Time statements.
\timing on

-- Transaction behaviour settings.
\set ON_ERROR_STOP on
\set ON_ERROR_ROLLBACK interactive

-- History settings.
-- Ignore duplicate entries if the same command was run more than once.
\set HISTCONTROL ignoredups
-- Use a sepearate history file for each database.
\set HISTFILE ~/.psql_history- :DBNAME

-- Helpful aliases.

-- > :version -- gives psql version output
\set version    'SELECT version();'

-- > :extensions  -- lists all available extensions
\set extensions 'SELECT * FROM pg_available_extensions;'

-- > :settings  -- shows all psql settings and their values
\set settings   'SELECT name, setting,unit,context FROM pg_settings;'

-- > :uptime  -- how long has this thing been up?
\set uptime     'SELECT now() - pg_postmaster_start_time() AS uptime;'

-- Restore echo.
\unset QUIET

\echo 'Loaded config from ~/.psqlrc';
```
</details>

## Mounting in Docker

If you run your Postgres instance in a Docker container, it can be useful to be able to use your settings when connecting to it.
The official PostgreSQL Docker image is configured to use the _/etc/postgresql-common/psqlrc_ file for psql. You can easily mount
your own file with the `--mount` flag as follows:

```sh
docker run --mount ./pgdata:/var/lib/postgres \
           --mount type=bind,source=.psqlrc,target=/etc/postgresql-common/psqlrc,readonly \
           -p 5432:5432 \
           postgres:latest
```

I have included a few additional flags, which I usually use when spinning up a Postgres sandbox.
First mount point is for the data volume, specifying it will keep the database intact between container restarts.
Second mount option specifies that we want .psqlrc file visible in the container; read-only option is just for safety.
The `-p` flag exposes the standard Postgres port, so we can reach the database from host machine.
A corresponding docker compose file would look like this:

```yaml
version: '3.7'

services:
  database:
    # Official PostgreSQL docker image, latest version.
    image: postgres:latest
    # Exposed default ports.
    ports:
    - 5432:5432
    volumes:
    - ./pgdata:/var/lib/postgres
    # Mount psql config file in the system configuration directory.
    - type: bind
      source: .psqlrc
      target: /etc/postgresql-common/psqlrc
      read_only: true
```

## Summary

Postgres has a wonderful open-source tooling, that can be tweaked according to your needs or personal taste.
Even though there are much more advances and feature-rich clients, I still find it useful to know CLI tools,
especially if you're doing some rapid prototyping or need to quickly query a table or run a prepared script.
Psql can be also useful for generating simple html reports from SQL queries.
You can find my up-to-date .psqlrc file on my [GitHub page](https://github.com/bartelemi/dotfiles/blob/master/.psqlrc).
