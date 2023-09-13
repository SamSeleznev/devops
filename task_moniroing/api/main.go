package main

import (
    "context"
    "database/sql"
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"
    "time"

    "github.com/aws/aws-sdk-go/aws"
    "github.com/aws/aws-sdk-go/aws/session"
    "github.com/aws/aws-sdk-go/service/ec2"
    "github.com/go-redis/redis/v8"
    _ "github.com/lib/pq"
    "github.com/prometheus/client_golang/prometheus/promhttp"
    "github.com/rs/cors"
)

var (
    db          *sql.DB
    redisClient *redis.Client
)

func ensureTableExists() error {
    _, err := db.Exec(`CREATE TABLE IF NOT EXISTS ec2_instances (
        id TEXT PRIMARY KEY
    );`)
    return err
}

func initRedisClient() {
    redisClient = redis.NewClient(&redis.Options{
        Addr: "redis.tkkszs.ng.0001.apn2.cache.amazonaws.com:6379",
        DB:   0,
    })
}

func handlerHello(w http.ResponseWriter, r *http.Request) {
    var data struct {
        Name string `json:"name"`
    }

    err := json.NewDecoder(r.Body).Decode(&data)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    cachedResponse, err := redisClient.Get(context.Background(), "hello:"+data.Name).Result()
    if err == nil {
        fmt.Fprintln(w, cachedResponse)
        return
    }

    message := fmt.Sprintf("Hello, %s!", data.Name)
    redisClient.Set(context.Background(), "hello:"+data.Name, message, time.Minute)
    fmt.Fprintln(w, message)
}

func handlerCreateEC2Instance(w http.ResponseWriter, r *http.Request) {
    if err := ensureTableExists(); err != nil {
        http.Error(w, "Failed to create table: "+err.Error(), http.StatusInternalServerError)
        return
    }

    sess, err := session.NewSession(&aws.Config{
        Region: aws.String("ap-northeast-2"),
    })
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    svc := ec2.New(sess)
    runResult, err := svc.RunInstances(&ec2.RunInstancesInput{
        ImageId:          aws.String("ami-0c9c942bd7bf113a2"),
        InstanceType:     aws.String("t2.micro"),
        MinCount:         aws.Int64(1),
        MaxCount:         aws.Int64(1),
        SecurityGroupIds: aws.StringSlice([]string{"sg-02aecc7bf2b1840dc"}),
        KeyName:          aws.String("id_rsa"),
        TagSpecifications: []*ec2.TagSpecification{
            {
                ResourceType: aws.String("instance"),
                Tags: []*ec2.Tag{
                    {
                        Key:   aws.String("Name"),
                        Value: aws.String("UbuntuGo"),
                    },
                },
            },
        },
    })
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    instanceID := aws.StringValue(runResult.Instances[0].InstanceId)

    _, err = db.Exec("INSERT INTO ec2_instances (id) VALUES ($1)", instanceID)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    if err := json.NewEncoder(w).Encode(instanceID); err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    requestsTotal.Inc()
}

func handlerTerminateEC2Instance(w http.ResponseWriter, r *http.Request) {
    if err := ensureTableExists(); err != nil {
        http.Error(w, "Failed to create table: "+err.Error(), http.StatusInternalServerError)
        return
    }

    var data struct {
        InstanceId string `json:"instanceId"`
    }

    err := json.NewDecoder(r.Body).Decode(&data)
    if err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    sess, err := session.NewSession(&aws.Config{
        Region: aws.String("ap-northeast-2"),
    })
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    svc := ec2.New(sess)
    _, err = svc.TerminateInstances(&ec2.TerminateInstancesInput{
        InstanceIds: []*string{aws.String(data.InstanceId)},
    })
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    _, err = db.Exec("DELETE FROM ec2_instances WHERE id = $1", data.InstanceId)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    if _, err := w.Write([]byte("Instance terminated successfully!!!")); err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    requestsTotal.Inc()
}

func handlerHealth(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(http.StatusOK)
    if _, err := w.Write([]byte("OK")); err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
}

func main() {
    var err error
    dbUser := os.Getenv("DB_USER")
    dbPass := os.Getenv("DB_PASS")
    dbName := os.Getenv("DB_NAME")
    dbHost := os.Getenv("DB_HOST")

    connStr := fmt.Sprintf("user=%s password=%s dbname=%s host=%s sslmode=require", dbUser, dbPass, dbName, dbHost)
    db, err = sql.Open("postgres", connStr)
    if err != nil {
        log.Fatalf("Error connecting to database: %v", err)
    }
    initRedisClient()

    mux := http.NewServeMux()

    mux.HandleFunc("/api/hello", handlerHello)
    mux.HandleFunc("/api/ec2/create", handlerCreateEC2Instance)
    mux.HandleFunc("/api/ec2/terminate", handlerTerminateEC2Instance)
    mux.HandleFunc("/api/health", handlerHealth)

    http.Handle("/metrics", promhttp.Handler())

    handler := cors.Default().Handler(mux)

    go func() {
        log.Println("Starting Prometheus metrics server on port 8080...")
        log.Fatal(http.ListenAndServe(":8080", nil))
    }()

    log.Println("Starting application server on port 80...")
    err = http.ListenAndServe(":80", handler)
    if err != nil {
        log.Fatal("Error starting server: ", err)
    }
}
