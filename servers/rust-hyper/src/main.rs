use std::convert::Infallible;
use std::env;
use std::error::Error;
use std::io::{self, ErrorKind};
use std::net::{IpAddr, SocketAddr};

use http_body_util::Full;
use hyper::body::{Bytes, Incoming};
use hyper::header::{CONTENT_LENGTH, CONTENT_TYPE};
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{Method, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use tokio::net::{TcpListener, TcpSocket};
use tokio::runtime::Builder;

const DEFAULT_PORT: u16 = 8080;
const DEFAULT_BACKLOG: u32 = 1024;
const DEFAULT_WORKERS: usize = 1;
const HTTP1_MAX_BUFFER: usize = 16 * 1024;

fn main() -> Result<(), Box<dyn Error>> {
    let config = Config::parse(env::args().skip(1))?;

    let runtime = Builder::new_multi_thread()
        .worker_threads(config.workers)
        .enable_all()
        .build()?;

    runtime.block_on(run(config))
}

async fn run(config: Config) -> Result<(), Box<dyn Error>> {
    let listener = create_listener(&config)?;
    println!(
        "rust-hyper listening on http://{}:{} with {} worker(s)",
        config.host, config.port, config.workers
    );

    loop {
        tokio::select! {
            accept_result = listener.accept() => {
                let (stream, _) = accept_result?;
                stream.set_nodelay(true)?;

                tokio::spawn(async move {
                    let io = TokioIo::new(stream);
                    let service = service_fn(handle_request);
                    let mut builder = http1::Builder::new();
                    builder
                        .keep_alive(true)
                        .auto_date_header(false)
                        .max_buf_size(HTTP1_MAX_BUFFER)
                        .max_headers(100)
                        .writev(true);

                    let _ = builder.serve_connection(io, service).await;
                });
            }
            signal_result = tokio::signal::ctrl_c() => {
                signal_result?;
                break;
            }
        }
    }

    Ok(())
}

fn create_listener(config: &Config) -> Result<TcpListener, Box<dyn Error>> {
    let ip: IpAddr = config.host.parse()?;
    let address = SocketAddr::new(ip, config.port);

    let socket = match ip {
        IpAddr::V4(_) => TcpSocket::new_v4()?,
        IpAddr::V6(_) => TcpSocket::new_v6()?,
    };

    socket.set_reuseaddr(true)?;
    socket.bind(address)?;
    Ok(socket.listen(config.backlog)?)
}

async fn handle_request(request: Request<Incoming>) -> Result<Response<Full<Bytes>>, Infallible> {
    let response = if request.method() != Method::GET {
        text_response(StatusCode::METHOD_NOT_ALLOWED, b"Method Not Allowed\n")
    } else {
        match request.uri().path() {
            "/health" => text_response(StatusCode::OK, b"ok\n"),
            "/plaintext" => text_response(StatusCode::OK, b"Hello, World!\n"),
            _ => text_response(StatusCode::NOT_FOUND, b"Not Found\n"),
        }
    };

    Ok(response)
}

fn text_response(status: StatusCode, body: &'static [u8]) -> Response<Full<Bytes>> {
    let mut response = Response::new(Full::new(Bytes::from_static(body)));
    *response.status_mut() = status;

    let headers = response.headers_mut();
    headers.insert(CONTENT_TYPE, "text/plain".parse().expect("valid static header"));
    headers.insert(
        CONTENT_LENGTH,
        body.len().to_string().parse().expect("valid content length"),
    );

    response
}

#[derive(Debug)]
struct Config {
    host: String,
    port: u16,
    backlog: u32,
    workers: usize,
}

impl Config {
    fn parse<I>(arguments: I) -> Result<Self, Box<dyn Error>>
    where
        I: IntoIterator<Item = String>,
    {
        let mut host = String::from("127.0.0.1");
        let mut port = DEFAULT_PORT;
        let mut backlog = DEFAULT_BACKLOG;
        let mut workers = DEFAULT_WORKERS;

        let mut arguments = arguments.into_iter();
        while let Some(argument) = arguments.next() {
            match argument.as_str() {
                "--host" => host = require_value(&mut arguments, "--host")?,
                "--port" => {
                    port = require_value(&mut arguments, "--port")?.parse()?;
                }
                "--backlog" => {
                    backlog = require_value(&mut arguments, "--backlog")?.parse()?;
                    if backlog == 0 {
                        return Err(invalid_input("backlog must be positive").into());
                    }
                }
                "--workers" => {
                    workers = require_value(&mut arguments, "--workers")?.parse()?;
                    if workers == 0 {
                        return Err(invalid_input("workers must be positive").into());
                    }
                }
                _ => {
                    return Err(invalid_input(format!("unknown argument: {argument}")).into());
                }
            }
        }

        Ok(Self {
            host,
            port,
            backlog,
            workers,
        })
    }
}

fn require_value<I>(arguments: &mut I, option: &str) -> Result<String, Box<dyn Error>>
where
    I: Iterator<Item = String>,
{
    arguments
        .next()
        .ok_or_else(|| invalid_input(format!("missing value for {option}")).into())
}

fn invalid_input(message: impl Into<String>) -> io::Error {
    io::Error::new(ErrorKind::InvalidInput, message.into())
}
