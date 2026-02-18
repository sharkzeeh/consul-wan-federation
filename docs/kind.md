# kind

## Install `kind`

https://kind.sigs.k8s.io/docs/user/quick-start/

### Windows
- cmd
```
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.31.0/kind-windows-amd64
move kind-windows-amd64.exe C:\%USERPROFILE%\kind.exe
```

- powershell
```
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.31.0/kind-windows-amd64
Move-Item .\kind-windows-amd64.exe "$env:USERPROFILE\kind.exe"
```

- test
```
C:\Users\robez>kind
kind creates and manages local Kubernetes clusters using Docker container 'nodes'

Usage:
  kind [command]
```
