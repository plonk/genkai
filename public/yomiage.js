//
let $yomiage_board_id = null
let $yomiage_thread_id = null


// 外部に暴露するグローバル変数。
var $dat_size = null;
var $queue = [];
let $silentMode = false

async function getNewMessages() {
    console.log("getNewMessages");
    return new Promise((resolve, reject) =>
                       $.ajax(`/${$yomiage_board_id}/dat/${$yomiage_thread_id}.dat?long_polling=1&format=json`,
                              {
                                  headers: { Range: "bytes=" + $dat_size + "-" },
                                  cache: false,
                                  dataType: 'json',
                                  success: function(data, textStatus, jqXHR){
                                      resolve(data);
                                  },
                                  error: function(req, textStatus){
                                      reject(textStatus);
                                  },
                                  timeout: 120*1000,
                              }));
}

function htmlUnescape(str) {
    var textArea = document.createElement('textarea');
    textArea.innerHTML = str;
    return textArea.value;
}

function massage(text) { // もみもみ
    // メッセージを読み上げに適した形に修正する。
    text = text.replace(/ <br> /g, ' ');
    text = text.replace(/h?ttps?:\/\/[A-Za-z0-9+\/~_\-.]+/g, "[URL]");
    text = text.replace(/<a href="[^"]+">&gt;&gt;(\d+)<\/a>/g, (_, p1) => p1 + " ");
    text = text.replace(/&#x?\d+;/g, ""); // 数値実体参照を全削除する。

    // 繰り返しを省略する。
    let oldlength = text.length;
    while (true) {
        text = text.replace(/(.+?)\1{3,}/g, (m, c1) => { /* console.log(c1); */ return c1; });
        if (text.length === oldlength)
            break;
        else
            oldlength = text.length;
    }
    
    text = htmlUnescape(text);
    return text;
}

function speakHttpApi(text) {
    return new Promise(cont => {
        var req = new XMLHttpRequest();
        var params = `text=${encodeURI(text)}&format=ogg`;

        req.open("POST", "http://speech.pcgw.pgw.jp/v1/tts", true);
        req.responseType = 'blob';
        req.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');

        req.addEventListener('load', ev => {
            // レス着信音を鳴らして、500msのディレイの後にテキストの再生を始める。
            var au = new Audio(URL.createObjectURL(req.response));
            au.addEventListener("ended", _ => {
                cont();
            });
            var au2 = new Audio("/kiri2.wav");
            au2.addEventListener("ended", _ => {
                au.play().catch(err => {
                    console.log(err);
                    cont();
                });
            });
            au2.play().catch(err => {
                console.log(err);
                cont();
            });
        });
        req.addEventListener('error', ev => {
            console.log(ev);
            const au = new Audio('/failure.wav');
            au.addEventListener("ended", _ => {
                cont();
            });
            au.play().catch(err => {
                console.log(err);
                cont();
            });
        });
        req.send(params);
    });
}

function speakSpeechSynthesis(text) {
    return new Promise(cont => {
        const synth = window.speechSynthesis;
        var utter = new SpeechSynthesisUtterance(text);
        const voices = window.speechSynthesis.getVoices();
        utter.lang = "ja";

        var notify = new Audio("/kiri2.wav");
        notify.addEventListener("ended", _ => {
            utter.addEventListener("end", _ => {
                cont();
            });
            utter.addEventListener("error", ev => {
                console.log(ev);
                const au = new Audio('/failure.wav');
                au.addEventListener("ended", _ => {
                    cont();
                });
                au.play().catch(err => {
                    console.log(err);
                    cont();
                });
            });
            synth.speak(utter)
        });
        notify.play().catch(err => {
            console.log(err);
            cont();
        });
    });
}

function getInitialDatSize() {
    return new Promise((resolve, reject) =>
                       $.ajax(`/${$yomiage_board_id}/dat/${$yomiage_thread_id}.dat`,
                              {
                                  type: 'HEAD',
                                  cache: false,
                                  success: function(data, textStatus, jqXHR){
                                      console.log('$dat_size =', jqXHR.getResponseHeader('Content-Length'));
                                      $dat_size = +jqXHR.getResponseHeader('Content-Length');
                                      resolve($dat_size);
                                  },
                                  error: function(req, textStatus){
                                      reject(textStatus);
                                  },
                                  timeout: 5*1000,
                              }));
}

function delay(ms) {
    return new Promise((resolve, _reject) => setTimeout(resolve, ms));
}

