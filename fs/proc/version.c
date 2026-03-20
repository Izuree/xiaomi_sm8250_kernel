// SPDX-License-Identifier: GPL-2.0
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/utsname.h>
#include <linux/rcupdate.h>
#include <linux/cred.h>
#include <linux/sched.h>
#include <linux/capability.h>
#include <linux/e404_attributes.h>

#define FAKE_BANNER "Linux version 4.19.404R (vyn@zorin) (deutereum_VERSION_OVERRIDE) #1 SMP PREEMPT\n"

static bool is_allowed_process(void)
{
	struct task_struct *t = current;
	bool found = false;
	unsigned int i;

	rcu_read_lock();
	while (t->pid > 1) {
		t = rcu_dereference(t->real_parent);
		if (!t)
			break;
		uid_t uid = from_kuid(&init_user_ns, __task_cred(t)->uid);
		for (i = 0; i < proc_version_allowed_uids_count; i++) {
			if (uid == proc_version_allowed_uids[i]) {
				found = true;
				goto out;
			}
		}
	}
out:
	rcu_read_unlock();
	return found;
}

static int version_proc_show(struct seq_file *m, void *v)
{
	if (!capable(CAP_SYS_ADMIN))
		return -EPERM;

	if (proc_version_allowed_uids_count > 0 && is_allowed_process()) {
		seq_puts(m, FAKE_BANNER);
		return 0;
	}

	seq_printf(m, linux_proc_banner,
		utsname()->sysname,
		utsname()->release,
		utsname()->version);
	return 0;
}

static int __init proc_version_init(void)
{
	proc_create_single("version", S_IRUSR, NULL, version_proc_show);
	return 0;
}
fs_initcall(proc_version_init);