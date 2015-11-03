# volt-sql

**Note**: This is still a work in process.  We'll update this when the final version is out.

This gem provides postgres support for volt.  Just include it in your gemfile and the gem will do the rest.  It is included in new projects by default (currently).

```
gem 'volt-sql'
gem 'pg', '~> 0.18.2'
gem 'pg_json', '~> 0.1.29'
'
```


## Big Thanks

First off, I wanted to say a big thanks to @jeremyevans for his hard work on Sequel, without which, this gem would not be possible.

## How migrations work:

When an app boots in dev mode, or a file is changed in dev mode, and a new field is detected, the following happens:

if there are no orphan fields (fields that exist in the db, but not in the Models class):
  - the field is added

- If there is a single orphaned field and a single added field in the model:
  - a migration is generated to rename the field
  - the migration is run

- If there are multiple orphans or fields added
  - volt warns you and makes you deal with it (by creating migrations)