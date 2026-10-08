package com.company.messenger.file;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.LocalDate;
import java.util.UUID;

import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

import com.company.messenger.config.AppProperties;

/**
 * 파일 저장소 (PVC 마운트 경로).
 * 백엔드를 여러 Pod 로 운영할 경우 ReadWriteMany(RWX) PVC 를 사용해야 한다.
 */
@Component
public class FileStorage {

    private final Path root;

    public FileStorage(AppProperties props) throws IOException {
        this.root = Path.of(props.files().storagePath()).toAbsolutePath().normalize();
        Files.createDirectories(root);
    }

    public String store(InputStream in) throws IOException {
        LocalDate today = LocalDate.now();
        String key = "%d/%02d/%02d/%s".formatted(today.getYear(), today.getMonthValue(), today.getDayOfMonth(),
                UUID.randomUUID());
        Path target = resolve(key);
        Files.createDirectories(target.getParent());
        Files.copy(in, target, StandardCopyOption.REPLACE_EXISTING);
        return key;
    }

    public Resource load(String key) {
        return new FileSystemResource(resolve(key));
    }

    public void delete(String key) throws IOException {
        Files.deleteIfExists(resolve(key));
    }

    private Path resolve(String key) {
        Path p = root.resolve(key).normalize();
        if (!p.startsWith(root)) {
            throw new IllegalArgumentException("잘못된 파일 경로");
        }
        return p;
    }
}
