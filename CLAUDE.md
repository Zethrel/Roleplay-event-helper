# Working agreement

## Releases are cut by the maintainer, never by Claude

Do not cut a release unless asked for one in so many words. Cutting a release
means, and is limited to:

- bumping `## Version:` in `RoleplayEventHelper.toc`
- turning the `## Unreleased` section of `CHANGELOG.md` into a numbered version
- updating the version and check count in `README.md`
- building the distributable zip and sending it over
- tagging (`git tag -a vX.Y.Z`), which is what triggers the packaging workflow

None of that happens on Claude's initiative, however finished a change feels.

What does still happen by default, without being asked: running the test suites,
committing, and pushing to the working branch. The container is ephemeral, so
unpushed work is lost work.

## Every change gets a changelog entry

Write it as the change is made, not at release time, under a `## Unreleased`
heading at the top of `CHANGELOG.md`. Create that heading if it is not there.
When a release is finally cut, `## Unreleased` becomes `## X.Y.Z - date`.

Entries are written for the host reading the CurseForge page, not for the
person who wrote the diff:

- lead with what changed for them, not with the mechanism
- name the event or the moment it matters at ("reported from a fishing night:
  a 7 announced FAILURE and then reeled in a fat carp")
- say plainly when an existing preset is affected, and when it is not
- keep the internals for the commit message, which is where they belong

Also summarise the same change in the reply, so it can be judged without
opening the file.

## The tests

`./Tests/run.sh` runs every suite; `VERBOSE=1` shows each check. They run
against a stub of the WoW API in Lua 5.1, and the widget mock raises on any
method the real client does not have -- so building a frame under test is itself
proof the layout code calls nothing imaginary. Adding a method to the mock's
allowed list is a deliberate statement that the client has it.

Keep every suite green before committing.
