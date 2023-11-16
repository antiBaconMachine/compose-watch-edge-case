# Docker compose build + multi image + watch edge case

I love the new docker compose command, I want to use it everywhere. I found this minor annoyance and figured it was worth some time to document it.

## TL;DR;

In order to use docker compose watch we have to give a service a build context but for cases where one image is used to run multiple services this can change the behavior of other non watch commands. 

The [docs](https://docs.docker.com/compose/compose-file/build/#consistency-with-image) say that

> Compose with build support first tries to pull the image, then builds from source if the image is not found on registry

So our service which used to run using a local image now first pulls, and then builds from source. I can prevent the image pull with `pull_policy: never` however there is a further line in the [compose spec](https://github.com/compose-spec/compose-spec/blob/master/spec.md#pull_policy) which says

> If pull_policy and build are both present, Compose builds the image by default.

So there is currently no way to have an image built by one service _and_ used by another service _and_ have that service use docker compose watch.

## Example

I've made a contrived dummy project to show some of the issue 

```
git clone git@github.com:antiBaconMachine/compose-watch-edge-case.git
cd compose-watch-edge-case
docker compose up --build
```

Watch the output, there are two build runs, the second one is all cached. This simple example doesn't do a great job of demonstrating the problem because it's so small and fast. A larger project can have slower builds even when it is 100% cached.

From a different terminal

```
curl localhost:8080
```

Edit `api/src/hello.http` to see the watch behavior. You'll have to curl twice after making a change because of the cheap way I implemented the dummy server.

## Explanation

What I have is an api image which has a database migrator task. I want to run this migrator task as a seperate service and have the main api depend upon the successful completion of the migrator.

What I would like to do here is have the migrator build the image and tag it and then have the api run the tagged image.

```
services:

  api:
    image: acme.localhost/api
    depends_on:
      migrator:
        condition: service_completed_successfully
  
  migrator:
    image: acme.localhost/api
    build: ./api
    pull_policy: never
    command: /app/migrator.sh
```

However, with the introduction of watch I now need the api to have a build context so I have to replicate the build section from the migrator. This is not neccessarily a big deal as the build cache will be 100% utilised on the second run. However because it's 2023 imagine the api is stuffed full of packages, it's a behemoth. Also imagine I'm on mac or a windows machine running docker desktop with it's VM. The last steps of the build are exporting the layers and building a tarball. Even with full cache utilisation these steps can take seconds and I now have to do them twice.

```
services:

  api:
    image: acme.localhost/api
    build: ./api
    develop:
      watch:
        - action: sync
          path: ./api/src/hello.http
          target: /app/hello.http
    ports:
      - 8080:8080
    depends_on:
      migrator:
        condition: service_completed_successfully
  
  migrator:
    image: acme.localhost/api
    build: ./api
    pull_policy: never
    command: /app/migrator.sh
```

So what I'd like to be able to do is tell compose to always use the image for the api service even though there is a build section present.

## Workarounds

 * override file - I could create an override compose file which adds the build context and watch config and then have a wrapper script which activates the overlay on watch. Fine but adds complexity and new wrapper script to maintain.
 * Have the migrator task run in the entrypoint of the api. Fine but requires a custom entrypoint script, hides the detail from users of the service and generally breaks the do one thing well rule.

## Possible solutions

This is all speculative, I know nothing about the compose project I'm just thinking out loud.

* `pull_policy` addition - something like `pull_policy: local`. This is not quite right because what we really want is `pull_policy: never` _and_ some sort of `no_build` flag. I guess I could be convinced that `local` makes semantic sense.
* `develop` section flag - The new develop section currently just has watch stuff in it, could we use this space to add a watch specific build context? Not sure I like this, but it does neatly sidestep the issue with having build and image present at top level

I'd be happy to work on a solution if it would be welcome but as any soltuion is likely to require additions to compose spec I'd need an ok from maintainers first.

## Non solutions

I've seen a request for a CLI flag to do something similar to this but I don't see it as an ad hoc thing, I think it's more like `pull_policy`, a long term behavior which should always be present.

## Related issues

https://github.com/docker/compose/issues/9730 - similar but this specific case can be worked around through use of overrides
https://github.com/docker/compose/issues/9451 - The inverse issue
