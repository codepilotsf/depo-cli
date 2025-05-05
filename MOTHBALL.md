I don't have time for this right now. 

Next steps are to finish up the `depo apps` command and then `depo up`.

But I kinda love the ideas. Here are the notes I made while working on it:

# Depo Deployment Tool

### Inspiration

Kamal and Dokku are both Docker-based which means that deployment is a very heavyweight, cumbersome, and error-prone process. It really doesn't need to be that complicated!

Depo will use Rsync under the hood and will deploy to the target configured for your current git branch. It will also build a Ruby/Puma/Node server from a blank Ubuntu server.

### Typical upload workflow

Once the server is set up and a config file has been generated, it will work like this.

```bash
$ depo up

Deploy staging branch to staging.example.com? [Y/n] Y

✔ Creating release
✔ Copying secrets
✔ Uploading files
✔ Installing gems
✔ Running db migrations
✔ Precompiling assets
✔ Updating symlink
✔ Restarting web server
✔ Cleaning up

Finished.

$
```

### Forgot to commit Git?

```bash
$ depo up

Git working directory is unclean. 

Please commit your changes and try again.

$
```



### Installation

```bash
$ gem install depo-cli
```



### Set up server

```bash
$ depo setup

Hostname or IP address of remote server? 11.22.33.44

✔ Installing asdf
✔ Installing Ruby
✔ Installing Puma
✔ Installing Caddy
✔ Starting services

Finished.

$
```



### Big picture example

What's it look like to install depo for the first time, build a server, create a config and deploy an app. This assumes you're already cd'ed into a Rails application.

```bash
$ gem install depo
...
$ depo setup
...
$ depo init
...
$ depo up
...
$ 
```

Okay so those are the big three: `setup`, `init`, and `up`.

### `depo init`

Initially, I thought this should just create the config file – but actually, I think it should also create the user on the server in preparation for future `depo up` operations.

1. Prompt for new app new (initially populated with name of parent directory)

2. Generate a file at `config/depo.yml` with these contents:
   ```yaml
   # config/depo.yaml
   name: example
   host: example.com
   branches:
     main:
       name: production
       host: example.com
     staging:
       host: staging.example.com
     internal:
       host: internal.example.com
   ```

3. Connect to server as root and create a new user and home directory for this app, copy the local public key to the keychain so that the user who created this app user will have access.

4. Print message: Please update `config/depo.yml` with your connection details



Add a `depo shell` command as a shortcut to ssh into the user account for this app.



### All commands

```bash
# Any user
$ depo up # Upload files, run db migrations, etc
$ depo maintenance # Put the site in maintenance mode
$ depo console # Rails console
$ depo seed # Upload files, run db migrations, etc
$ depo logs # Shows last 100 lines plus tail -f
$ depo www # Set www redirect policy always, never, ignore (default)
$ depo https # Set https redirect policy always (default), never, ignore
$ depo vhost # Manually edit the vhost
$ depo shell # Shortcut to ssh in as this user

# Root user only
$ depo setup # Build server
$ depo apps # List all apps and show option to add, edit, destroy
$ depo keys # Show all ssh keys and show option to add or remove keys
```



### Root vs. regular user

It's becoming apparent that there are two classes of depo commands: root and regular user. Also... the idea of using the config file for things like redirects, or enforce www, etc -- this is a bad idea. If someone accidentally deletes a line, should that have a surprise destructive effect, the next time they use `depo up`? Probably not. Instead, let's use commands like Dokku does. 



### TODO

- Add MOTD message that warns on login to always use depo cli to manage 

- Add a `/var/lib/depo/data.yml`
  ```yaml
  # THIS NEEDS MORE THOUGHT...
  apps:
    herpderp:
    	enforce_http: true
    	branches:
    		main:
    			name: production
      		host: example.com
      		enforce_www: true
    	staging:
      	host: staging.example.com
      internal:
        host: internal.example.com
  ```

  

### Next

1. Update `setup` to add MOTD
2. Update `setup` to create a dir at `/var/lib/depo/` 
3. Add an `apps` command which lists apps found in `data.yml`, selectable, deletable, editable. Add an option to create a new app (use current init code and remove init command).

---

### BIG NEW THINKING

Since rbenv, rails, and puma all need to be installed on a per user basis, this actually simplifies some things. Like for example, we can install a different stack on a per user basis. Maybe this means we can use asdf again since it seemed that the trouble involved root user specifically. But also, this might mean we don't need to use `init`. Just use `up` and the first time you do, if no config is found with a username and host, it will prompt you for those (and later prompt for which stack you want to use). If there's a host and username but no matching branch, then you'll get prompted "Do you want to add a new deployment target for the 'foobar' branch?" – so theoretically, the user doesn't need to use `depo init` at all *and* doesn't even need to manually edit the config for basic deployment. 

### Prompt for first phase of `depo up`

I want to add `depo up` which will eventually use rsync to upload a Rails app, add a vhost to Caddy, etc -- but for now, I only want it to do the following: 

- Check to see if pwd is inside of a Rails application, if not, abort with message 
- If no config/depo.yml exists in Rails root directory, create one (with message to user "Creating config/depo.yml")
- If no `name` property exists in depo.yml, prompt for one (default to name of app root directory) and save to depo.yml.
- If depo.yml is missing `branches.<current-git-branch>`, or `branches.<current-git-branch>` is missing either `host` or `username`, prompt for it and save to depo.yml. Host should default to `<current-branch>.<name>.com` unless `current-branch` is `main` – then the default should be `www.<name>.com`. Username should default to `<name>-<branch>`
- Check connection and if ssh connection fails, abort with error.
- If ssh connection succeeds, use code from `init` to create new user, then add a file `<username>.yml` and `<username>.caddy` to `/var/lib/depo/`
- If that succeeds, prompt user for environment name (defaults to current branch) and hostname which defaults to current branch -dot- username -dot- com

### Caddy vhosts

```
import /var/lib/depo/*.caddy
```

### Crap -- users vs. environments

I'm sorta counting on the idea that everyone will always want to deploy all of their environments to the same server into a directory owned by the same user. This is a bad plan for a few reasons. First, what if I want to deploy staging to a different machine? What if I want to add a new dev to have access to internal -- but definitely not have the ability to fuck up production. 

Okay so simple solution: There's no umbrella username or host or concept of an "app" with "environments" – there's only "apps" – that's it. And nothing is ever shared (like hostname or username). They are completely standalone.

So this simplifies using `depo up` too. Because it only needs to look for a matching key in `branches` in the config/depo.yml to find a `host` and `username`.

---

WAIT! If `up` is how we auto-create new branches in depo.yml, and if that's now creating a new user on the server, that means only root can do this. So then if I'm root and I want to give devs access to only this application, I have to first create or clone the Rails app – I'd rather just create the target environment, and let the dev take it from there.

So the ideal workflow is, I run `depo setup` to build the server, then `depo apps` to create `example-internal`, `example-staging`, and `example-main`. When creating each of these, I'm prompted to add SSH keys. So I add both Shashi and Zac's keys for example for each one.

Workflow improvement... Add keys to the server which are stored in /var/lib/depo/keys/. Then when I want to add keys for an app, I can just select one or more from the list of available keys on the server.

---

Okay managing SSH keys is a big feature. For now, let's keep things simple 

### Okay, new plan: start with `depo apps`

1. Start with `depo apps`
   - Log in as root user, list all apps in vhosts dir
   - Admin can create new or select an app to delete (or later to add ssh key access)
   - `depo apps` -> add new app
     - Creates new user and homedir
     - Installs asdf and ruby
     - Adds vhost to server with temp stub html for now
   - `depo apps` -> delete
     - Warning and confirmation
     - Remove user, remove vhost
   - `depo apps` -> add ssh keys
     - Todo
2. Next, `depo up`
   - Check for config with host and username
   - Prompt for host and username if not present
   - Attempt login, on success write to config
   - Rsync all files 
   - Run db migrations



### Simplify by removing username from view?

Why not just follow these rules

1. An app's name is its hostname. Ex: staging.notastic.app
2. The username is exactly the same (yes, usernames may have dots)
3. Now we only have to communicate one item to devs. 

So the new `depo.yml` is now ridiculously simple:
```yaml
internal: internal.example.com
staging: staging.example.dom
main: www.example.com
```

...and if we want to get more complex at some point:

```yaml
internal: 
	host: internal.example.com
	migrations: false
	exclude:
		- notes/
		- secret-stuff/
```

