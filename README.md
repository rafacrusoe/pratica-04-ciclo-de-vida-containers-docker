# Prática 04 - Gestão do ciclo de vida de contêineres Docker

Projeto desenvolvido para a disciplina **Práticas Integradas Full Cycle**. O repositório executa as quatro ações do roteiro: ciclo de vida de um contêiner Nginx, interação e logs, análise de recursos e métodos de remoção.

## Estrutura

- `scripts/run-all.sh`: executa todas as ações e grava as evidências.
- `scripts/analyze_stats.py`: calcula os maiores valores de CPU e memória observados.
- `.github/workflows/pratica-docker.yml`: executa a prática em um runner Linux com Docker.
- `evidencias/`: recebe os resultados gerados durante a execução.

## Como executar

Requisitos: Linux, Docker em execução, Bash, Python 3 e `curl`.

```bash
chmod +x scripts/run-all.sh
bash scripts/run-all.sh
```

Os resultados serão gravados em `evidencias/`.

## Ações realizadas

1. Criação, início, pausa, retomada e parada do contêiner `webserver`.
2. Requisições HTTP, logs e comandos executados dentro do Nginx.
3. Monitoramento de MySQL, Redis e Nginx antes, durante e após uma carga.
4. Remoção normal, tentativa de remoção em execução, remoção forçada, `--rm` e `container prune`.

> No GitHub Actions, a interação equivalente a `docker exec -it webserver bash` é automatizada com `docker exec webserver bash -lc`, pois o job não possui terminal humano interativo.

