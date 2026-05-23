# Stage cozy/kit/files/home/repos/cozy/ from the repo's source dirs, ready
# for `sbx run shell --kit ./kit/` or `sbx kit pack ./kit/`.
#
# Why a stage step instead of committing files/ to git: the kit's `files/`
# tree must mirror the four source dirs (cozy-module, docker-files,
# vendor, toolkit) at a nested path (home/repos/cozy/). Committing the
# nested layout would either duplicate content or rely on symlinks that
# `sbx kit pack` may or may not resolve. A pack step keeps the repo flat
# and makes kit assembly explicit.

const cozy_root = path self | path dirname | path dirname

let dst = $cozy_root | path join 'kit' 'files' 'home' 'repos' 'cozy'

if ($dst | path exists) { rm -rf $dst }
mkdir $dst

# Mirror the four subdirs verbatim. toolkit/ is included for completeness
# even though bootstrap.nu only invokes toolkit/vendor.nu when vendor/ is
# empty or --local is passed (neither happens with a pre-populated kit).
for sub in [cozy-module docker-files vendor toolkit] {
    ^cp -r ($cozy_root | path join $sub) $dst
}

let kit_dir = $cozy_root | path join 'kit'
print $"Kit assembled at ($kit_dir)"
print $"Run: sbx run shell --kit ($kit_dir)"
