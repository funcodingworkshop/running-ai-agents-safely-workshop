# AI Agents in Docker vision

A lot of development now can be done using autonomouse agents which has a lot of access grants and can run for a long period of time.

That implies different kinds of risks like: 

- prompt inections, 
- over previlaged access,
- big blast radius,
- data exfiltration, 
- insufficient oversight of irreversable actions,
- tool and supply chaine compromise
- memory and state poisoning

To address these risks I would like to run agents in docker container. So the development process should be as following:

- I build a docker image, which contains all necessary and sufficient for development.
  - volume with my project, for example tic-tac-toe folder
  - installed tools for visual tests
  - installed claude code tools
  - mapping of my claude auth credentials .claude-mike
  - internet access so that claude code could run
  - ideally I would like to limit all other internet access from the container
  - and if there is access it should have clear browser without my personal cookies and other stuff which is present in my Chrome
- and start a docker container
- I connect into docker container and write a prompt
- claude has all necessary preveliges in container to work on my request, to run unit and visual tests, etc.
- however claude access writes only limited to the mapped volume with the source code
- once task is finished I review it and commit
