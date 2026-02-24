#!/usr/bin/env nu

const self = path self | path dirname | path join todo.nu

use todo.nu create-todo

create-todo
