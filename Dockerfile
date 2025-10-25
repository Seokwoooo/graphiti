# 베이스 이미지: 가볍고 최신 파이썬
FROM python:3.12-slim

########################################
# 1. 기본 OS 패키지 설치
#    - curl: uv 설치 스크립트 받으려고 필요
#    - build-essential: (필요 시) 빌드 툴
#    - ca-certificates: TLS (neo4j+s:// 등) 연결 안정화
########################################
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl build-essential ca-certificates && \
    rm -rf /var/lib/apt/lists/*

########################################
# 2. uv 설치
#    uv = 파이썬 패키지/런처 (graphiti가 예제로 쓰는 방식)
#    기본 설치 경로는 /root/.local/bin/uv
########################################
RUN curl -fsSL https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

########################################
# 3. 애플리케이션 코드 컨테이너에 복사
########################################
WORKDIR /app
COPY . /app

########################################
# 4. 의존성 설치
#    graphiti MCP 서버 쪽은 mcp_server/ 디렉토리에
#    pyproject.toml, uv.lock 등이 있고
#    거기를 기준으로 env를 준비해야 함.
#
#    여기서 uv sync를 빌드 타임에 수행해서
#    런타임 때 즉시 실행할 수 있게 해둔다.
########################################
RUN uv sync --directory /app/mcp_server

########################################
# 5. uv 권한/경로 고정
#    문제였던 부분:
#    - uv는 /root/.local/bin/uv 밑에만 설치되어 있고
#      기본 권한상 root만 실행 가능한 경우가 생김
#    - 컨테이너는 나중에 일반 유저(app)로 돌릴 거라
#      Permission denied 터졌었음
#
#    해결:
#    - uv를 /usr/local/bin/uv 로 복사하고
#      전 유저 실행 가능(755) 권한 부여
########################################
RUN install -m 755 /root/.local/bin/uv /usr/local/bin/uv
ENV PATH="/usr/local/bin:${PATH}"

########################################
# 6. 런타임 환경변수(기본값)
#    PORT은 Render가 실제로 덮어씌울 예정이라
#    여기선 기본값만 넣어둔다.
#
#    DATABASE_TYPE / MODEL_NAME 등은 기본값만 넣어두고,
#    민감한 값:
#      OPENAI_API_KEY
#      NEO4J_URI
#      NEO4J_USER
#      NEO4J_PASSWORD
#    등은 절대 여기 넣지 말고
#    Render 대시보드의 Environment Variables에서 설정.
########################################
ENV PORT=8000
ENV DATABASE_TYPE=neo4j
ENV MODEL_NAME=gpt-4o-mini
ENV SMALL_MODEL_NAME=gpt-4o-mini
ENV GRAPHITI_TELEMETRY_ENABLED=false
ENV SEMAPHORE_LIMIT=10

########################################
# 7. 비루트 유저 생성
#    - 보안/격리 목적
#    - /app 디렉토리 권한을 넘겨서
#      이후 CMD가 root가 아닌 app 유저로 실행되도록
########################################
RUN useradd -m app && chown -R app:app /app
USER app

########################################
# 8. 네트워크 노출
#    Render 쪽에서도 이 포트를 기준으로
#    헬스 체크 / 라우팅이 붙는다.
########################################
EXPOSE 8000

########################################
# 9. 컨테이너 시작 커맨드
#
#    핵심 포인트:
#    - graphiti_mcp_server.py 가 "기억 MCP 서버"
#      즉 Claude가 붙어서 대화기억 저장/검색하는 서버임
#    - --transport sse 로 띄우면 /sse 엔드포인트가 생김
#      Claude Code 는 ~/.claude.json 에서
#      "type": "sse", "url": ".../sse" 로 이걸 물 수 있음
#    - --host 0.0.0.0 / --port $PORT
#      Render 컨테이너 외부에서 접근 가능하게 열어줌
#      ($PORT 는 Render가 runtime에 주입)
#    - --model / --group-id
#      memory 네임스페이스(apa)랑 내부 LLM 설정
#
#    sh -c 로 감싼 이유:
#    - $PORT 같은 env 변수를 쉘이 치환해주게 하려고
#    - 그리고 uv run을 app 유저 권한으로 실행
########################################
CMD ["sh", "-c", "uv run --directory /app/mcp_server graphiti_mcp_server.py --transport sse --host 0.0.0.0 --port $PORT --model gpt-4o-mini --group-id apa"]
