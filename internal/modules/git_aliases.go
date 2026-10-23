package modules

// gitAliasConfig 是 git 别名配置的唯一来源（自 Bash 时代 lib/git.sh 迁移而来，
// Bash 已于 0.4.0 退役，此处即权威；改动请同时更新 git_aliases 相关测试）。
const gitAliasConfig = `[diff]
    submodule = log

[pager]
    branch = false

[pull]
    rebase = false

[color]
    ui = auto

[alias]
    # ── Config ──
    cfg = config --global --list
    cfl = config --local --list
    cfs = config --system --list
    cfw = config --worktree --list

    # ── Log (美化日志) ──
    l = log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset %C(bold yellow) by %an' --abbrev-commit --date=relative --decorate
    la = log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset %C(bold yellow) by %an' --abbrev-commit --date=relative --decorate --all
    lm = log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative --decorate --author="$(git config user.name)"
    lma = log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative --decorate --author="$(git config user.name)" --all
    lc = log --oneline -n 10
    lg = log --graph --oneline --decorate --all
    lgs = log --stat -n 1
    lgt = log --oneline --since="2 weeks ago"
    lgb = log --oneline --branches
    lgr = log --oneline --remotes
    lgtg = log --oneline --tags

    # ── Branch ──
    b = branch
    br = branch -r
    bv = branch -vv
    bd = branch -d
    bD = branch -D
    bu = branch -u

    # ── Pull / Push ──
    pl = pull
    plrs = pull --recurse-submodules --ff-only
    plrb = pull --rebase
    pu = push
    pm = push --mirror
    po = push origin
    pof = push origin -f
    poh = push origin HEAD
    pot = push origin --tags
    poa = push origin --all
    pofs = push origin --force-with-lease

    # ── Add / Commit ──
    a = add
    c = commit
    ca = commit --amend
    cm = commit -m

    # ── Checkout ──
    co = checkout
    cb = checkout -b

    # ── Clone ──
    cl = clone
    cdf = clean -dxf
    clrs = clone --recurse-submodules

    # ── Cherry Pick ──
    pk = cherry-pick
    pkc = cherry-pick --continue
    pka = cherry-pick --abort

    # ── Diff ──
    d = diff
    dsm = diff --submodule

    # ── Merge ──
    m = merge
    mc = merge --continue
    ma = merge --abort

    # ── Status ──
    s = status
    ss = status -s

    # ── Stash ──
    st = stash
    sl = stash list
    sp = stash pop

    # ── Tag ──
    t = tag
    tl = tag -l
    td = tag -d

    # ── Submodule ──
    sm = submodule
    smi = submodule init
    smu = submodule update
    sms = submodule sync
    smur = submodule update --remote
    smuir = submodule update --init --recursive

    # ── Remote ──
    r = remote
    ra = remote add
    rv = remote -v
    rp = remote prune
    rpo = remote prune origin

    # ── Restore / Reset / Revert ──
    dp = restore
    re = restore
    ic = update-index --assume-unchanged
    uic = update-index --no-assume-unchanged
    rst = reset
    rsth = reset --hard HEAD
    rvt = revert

    # ── Rebase ──
    rb = rebase
    rbc = rebase --continue
    rba = rebase --abort
    rbi = rebase -i
    rbir = rebase -i --root

    # ── Worktree ──
    wt = worktree
    wta = worktree add
    wtl = worktree list
    wtr = worktree remove
    wtm = worktree move
    wtp = worktree prune

    # ── Format Patch ──
    fp = format-patch
    fp1 = format-patch -1
    ap = am

    # ── Misc ──
    h = config --global --list
    sh = !git --no-pager show HEAD
`
